#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>
#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#define JSNOW_PAUSE() _mm_pause()
#else
#define JSNOW_PAUSE() std::this_thread::yield()
#endif

namespace jsnow {

// Minimal fork-join pool. run(count, f) calls f(index, threadId) for every
// index in [0, count) with dynamic scheduling; the calling thread takes part as
// thread 0. Workers spin briefly between jobs (frames issue several jobs
// back-to-back) and then sleep on a condition variable.
class ThreadPool {
 public:
  explicit ThreadPool(int threads) : n_(threads < 1 ? 1 : threads) {
    for (int t = 1; t < n_; ++t) workers_.emplace_back([this, t] { loop(t); });
  }
  ~ThreadPool() {
    {
      std::lock_guard<std::mutex> lk(m_);
      stop_ = true;
      gen_.fetch_add(1, std::memory_order_release);
    }
    cv_.notify_all();
    for (auto& w : workers_) w.join();
  }
  int size() const { return n_; }

  template <class F>
  void run(int count, F&& f) {
    if (count <= 0) return;
    if (n_ == 1 || count == 1) {
      for (int i = 0; i < count; ++i) f(i, 0);
      return;
    }
    using Fn = std::remove_reference_t<F>;
    ctx_ = const_cast<void*>(static_cast<const void*>(&f));
    job_ = [](void* c, int i, int t) { (*static_cast<Fn*>(c))(i, t); };
    count_ = count;
    next_.store(0, std::memory_order_relaxed);
    pending_.store(n_ - 1, std::memory_order_relaxed);
    {
      std::lock_guard<std::mutex> lk(m_);
      gen_.fetch_add(1, std::memory_order_release);
    }
    cv_.notify_all();
    work(0);
    while (pending_.load(std::memory_order_acquire) != 0) JSNOW_PAUSE();
  }

 private:
  void work(int tid) {
    for (;;) {
      int i = next_.fetch_add(1, std::memory_order_relaxed);
      if (i >= count_) break;
      job_(ctx_, i, tid);
    }
  }
  void loop(int tid) {
    uint64_t seen = 0;
    for (;;) {
      int spins = 0;
      while (gen_.load(std::memory_order_acquire) == seen && spins < 200000) {
        JSNOW_PAUSE();
        ++spins;
      }
      if (gen_.load(std::memory_order_acquire) == seen) {
        std::unique_lock<std::mutex> lk(m_);
        cv_.wait(lk, [&] { return gen_.load(std::memory_order_acquire) != seen; });
      }
      seen = gen_.load(std::memory_order_acquire);
      if (stop_) return;
      work(tid);
      pending_.fetch_sub(1, std::memory_order_acq_rel);
    }
  }

  int n_;
  std::vector<std::thread> workers_;
  std::mutex m_;
  std::condition_variable cv_;
  std::atomic<uint64_t> gen_{0};
  std::atomic<int> next_{0};
  std::atomic<int> pending_{0};
  int count_ = 0;
  void* ctx_ = nullptr;
  void (*job_)(void*, int, int) = nullptr;
  bool stop_ = false;
};

}  // namespace jsnow
