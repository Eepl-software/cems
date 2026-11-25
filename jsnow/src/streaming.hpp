#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#include "scene.hpp"

namespace jsnow {

// LOD streaming. LOD0/LOD1 of every object start out non-resident: their
// region of the mesh arrays is zeroed and the data lives in a separate backing
// store (stand-in for the disk). Passes ask for the LOD they want; the finest
// resident LOD at or coarser than it is drawn (the coarsest LOD is always
// resident) and a load is queued. A background thread serves the queue
// nearest-first, copies the data back into place, throttles itself to the
// configured bandwidth and evicts least-recently-used entries over the budget.
class Streamer final : public LodProvider {
 public:
  Streamer(Scene& scene, size_t budgetBytes, double bandwidthMBs, double latencyMs = 2.0);
  ~Streamer();
  void beginFrame();
  int pick(size_t object, int desired, float distance) const override;

  struct Stats {
    double residentMB = 0, streamedMB = 0;
    size_t loads = 0, evictions = 0;
    size_t picks = 0, fallbacks = 0;  // since the last beginFrame
  };
  Stats stats() const;

 private:
  struct Entry {
    size_t object = 0;
    int lod = 0;
    size_t bytes = 0;
    std::vector<uint8_t> blob;  // backing store
    std::atomic<bool> resident{false};
    std::atomic<bool> queued{false};
    std::atomic<int> lastUsed{-1000};
    float priority = 0;
  };
  void load(Entry& e);
  void worker();

  Scene& scene_;
  size_t budget_;
  double bandwidth_, latencyMs_;
  std::vector<std::vector<int>> index_;  // object -> entry index per lod (-1 = always resident)
  std::vector<Entry> entries_;
  std::atomic<int> frame_{0};
  std::atomic<size_t> residentBytes_{0}, streamedBytes_{0}, loads_{0}, evictions_{0};
  mutable std::atomic<size_t> picks_{0}, fallbacks_{0};
  mutable std::mutex m_;
  mutable std::condition_variable cv_;
  mutable std::vector<int> queue_;
  bool stop_ = false;
  std::thread thread_;
};

}  // namespace jsnow
