#include "streaming.hpp"

#include <algorithm>
#include <chrono>
#include <cstring>

namespace jsnow {

namespace {
// Per-vertex streams and per-triangle streams of the mesh.
template <class F>
void forEachStream(Mesh& m, F&& f) {
  for (auto* v : {&m.px, &m.py, &m.pz, &m.nx, &m.ny, &m.nz, &m.tu, &m.tv}) f(*v, true);
}
}  // namespace

Streamer::Streamer(Scene& scene, size_t budgetBytes, double bandwidthMBs, double latencyMs)
    : scene_(scene), budget_(budgetBytes), bandwidth_(bandwidthMBs), latencyMs_(latencyMs) {
  Mesh& m = scene.mesh;
  size_t n = 0;
  for (const Object& o : scene.objects) n += size_t(std::max(0, o.lodCount - 1));
  entries_ = std::vector<Entry>(n);
  index_.resize(scene.objects.size());
  size_t k = 0;
  for (size_t oi = 0; oi < scene.objects.size(); ++oi) {
    const Object& o = scene.objects[oi];
    index_[oi].assign(3, -1);
    for (int l = 0; l + 1 < o.lodCount; ++l) {  // the coarsest LOD stays resident
      Entry& e = entries_[k];
      e.object = oi;
      e.lod = l;
      const LodRange& r = o.lod[l];
      // Serialise: 8 vertex streams, indices, per-triangle materials.
      const size_t vb = size_t(r.vertexCount) * sizeof(float), ib = size_t(r.indexCount) * sizeof(uint32_t);
      const size_t tb = size_t(r.indexCount / 3) * sizeof(uint16_t);
      e.bytes = 8 * vb + ib + tb;
      e.blob.resize(e.bytes);
      uint8_t* p = e.blob.data();
      forEachStream(m, [&](std::vector<float>& v, bool) {
        std::memcpy(p, v.data() + r.firstVertex, vb);
        std::memset(v.data() + r.firstVertex, 0, vb);  // not resident: zeroed region
        p += vb;
      });
      std::memcpy(p, m.idx.data() + r.firstIndex, ib);
      std::fill(m.idx.begin() + r.firstIndex, m.idx.begin() + r.firstIndex + r.indexCount, r.firstVertex);
      p += ib;
      std::memcpy(p, m.triMat.data() + r.firstIndex / 3, tb);
      index_[oi][l] = int(k);
      ++k;
    }
  }
  thread_ = std::thread([this] { worker(); });
}

Streamer::~Streamer() {
  {
    std::lock_guard<std::mutex> lk(m_);
    stop_ = true;
  }
  cv_.notify_all();
  thread_.join();
}

void Streamer::beginFrame() {
  frame_.fetch_add(1);
  picks_ = 0;
  fallbacks_ = 0;
}

int Streamer::pick(size_t object, int desired, float distance) const {
  const Object& o = scene_.objects[object];
  ++picks_;
  int lod = desired;
  for (; lod < o.lodCount; ++lod) {
    const int ei = index_[object][lod];
    if (ei < 0) break;  // always resident
    Entry& e = const_cast<Entry&>(entries_[ei]);
    if (e.resident.load(std::memory_order_acquire)) break;
  }
  if (lod != desired) {
    ++fallbacks_;
    Entry& want = const_cast<Entry&>(entries_[index_[object][desired]]);
    if (!want.queued.exchange(true)) {
      std::lock_guard<std::mutex> lk(m_);
      want.priority = distance;
      queue_.push_back(index_[object][desired]);
      cv_.notify_one();
    }
  }
  const int used = index_[object][lod];
  if (used >= 0) const_cast<Entry&>(entries_[used]).lastUsed.store(frame_.load(), std::memory_order_relaxed);
  return lod;
}

void Streamer::load(Entry& e) {
  Mesh& m = scene_.mesh;
  const LodRange& r = scene_.objects[e.object].lod[e.lod];
  const size_t vb = size_t(r.vertexCount) * sizeof(float), ib = size_t(r.indexCount) * sizeof(uint32_t);
  const size_t tb = size_t(r.indexCount / 3) * sizeof(uint16_t);
  const uint8_t* p = e.blob.data();
  forEachStream(m, [&](std::vector<float>& v, bool) {
    std::memcpy(v.data() + r.firstVertex, p, vb);
    p += vb;
  });
  std::memcpy(m.idx.data() + r.firstIndex, p, ib);
  p += ib;
  std::memcpy(m.triMat.data() + r.firstIndex / 3, p, tb);
}

void Streamer::worker() {
  using clk = std::chrono::steady_clock;
  for (;;) {
    int ei;
    {
      std::unique_lock<std::mutex> lk(m_);
      cv_.wait(lk, [&] { return stop_ || !queue_.empty(); });
      if (stop_) return;
      // Nearest request first.
      auto best = std::min_element(queue_.begin(), queue_.end(),
                                   [&](int a, int b) { return entries_[a].priority < entries_[b].priority; });
      ei = *best;
      queue_.erase(best);
    }
    Entry& e = entries_[ei];
    // Make room: evict least-recently-used entries not used in the last 2 frames.
    const int now = frame_.load();
    while (residentBytes_ + e.bytes > budget_) {
      Entry* victim = nullptr;
      for (Entry& c : entries_)
        if (c.resident.load() && c.lastUsed.load() < now - 2 && (!victim || c.lastUsed.load() < victim->lastUsed.load()))
          victim = &c;
      if (!victim) break;
      victim->resident.store(false, std::memory_order_release);
      residentBytes_ -= victim->bytes;
      ++evictions_;
    }
    if (residentBytes_ + e.bytes > budget_) {  // nothing evictable yet: retry later
      e.queued = false;
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
      continue;
    }
    auto t0 = clk::now();
    load(e);
    // Simulated device: fixed latency + bandwidth limit.
    const double ms = latencyMs_ + double(e.bytes) / (bandwidth_ * 1e6) * 1e3;
    const auto target = t0 + std::chrono::microseconds(int64_t(ms * 1000));
    std::this_thread::sleep_until(target);
    residentBytes_ += e.bytes;
    streamedBytes_ += e.bytes;
    ++loads_;
    e.resident.store(true, std::memory_order_release);
    e.queued = false;
  }
}

Streamer::Stats Streamer::stats() const {
  Stats s;
  s.residentMB = residentBytes_.load() / 1e6;
  s.streamedMB = streamedBytes_.load() / 1e6;
  s.loads = loads_.load();
  s.evictions = evictions_.load();
  s.picks = picks_.load();
  s.fallbacks = fallbacks_.load();
  return s;
}

}  // namespace jsnow
