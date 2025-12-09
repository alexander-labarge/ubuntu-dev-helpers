#!/usr/bin/env python3
"""
Tests for the worker_pool module
"""

import asyncio
import tempfile
import time
from pathlib import Path
import hashlib

from worker_pool import (
    WorkerPool,
    WorkerConfig,
    WorkerType,
    FileUploadWorker,
    FileDownloadWorker
)


def sample_task(value: int) -> int:
    """Simple task for testing"""
    time.sleep(0.1)  # Simulate work
    return value * 2


def compute_hash(data: bytes) -> str:
    """Compute SHA-256 hash of data"""
    return hashlib.sha256(data).hexdigest()


async def test_worker_pool_basic():
    """Test basic worker pool functionality"""
    print("\n[TEST 1] Testing basic worker pool...")
    
    config = WorkerConfig(max_workers=4, worker_type=WorkerType.THREAD)
    pool = WorkerPool(config)
    await pool.start()
    
    # Submit a single task
    result = await pool.submit_task("task1", sample_task, 5)
    
    assert result.success, f"Task failed: {result.error}"
    assert result.result == 10, f"Expected 10, got {result.result}"
    print(f"  ✓ Single task completed: {result.result}")
    
    await pool.shutdown()
    print("  ✓ Worker pool basic test passed")


async def test_worker_pool_batch():
    """Test batch task submission"""
    print("\n[TEST 2] Testing batch task submission...")
    
    config = WorkerConfig(max_workers=4, worker_type=WorkerType.THREAD)
    pool = WorkerPool(config)
    await pool.start()
    
    # Submit multiple tasks
    tasks = [
        (f"task_{i}", sample_task, (i,), {})
        for i in range(10)
    ]
    
    results = await pool.submit_batch(tasks)
    
    assert len(results) == 10, f"Expected 10 results, got {len(results)}"
    assert all(r.success for r in results), "Some tasks failed"
    
    expected = [i * 2 for i in range(10)]
    actual = [r.result for r in results]
    assert actual == expected, f"Expected {expected}, got {actual}"
    
    print(f"  ✓ Batch of {len(results)} tasks completed successfully")
    
    # Check metrics
    metrics = pool.get_metrics()
    print(f"  ✓ Metrics: {metrics['completed_tasks']}/{metrics['total_tasks']} completed")
    
    await pool.shutdown()
    print("  ✓ Worker pool batch test passed")


async def test_file_upload_worker():
    """Test file upload worker"""
    print("\n[TEST 3] Testing file upload worker...")
    
    # Create a temporary test file
    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.txt') as f:
        test_data = b"Hello, ARBOR! " * 1000  # ~14KB
        f.write(test_data)
        temp_file = Path(f.name)
    
    try:
        config = WorkerConfig(max_workers=4, worker_type=WorkerType.THREAD)
        pool = WorkerPool(config)
        await pool.start()
        
        upload_worker = FileUploadWorker(pool)
        
        # Process file in chunks
        chunk_size = 1024  # 1KB chunks
        results = await upload_worker.upload_file_parallel(
            temp_file,
            chunk_size=chunk_size
        )
        
        assert all(r.success for r in results), "Some chunks failed"
        print(f"  ✓ File processed in {len(results)} chunks")
        
        # Verify total bytes processed
        total_bytes = sum(r.result.get("chunk_size", 0) for r in results)
        assert total_bytes == len(test_data), f"Expected {len(test_data)} bytes, got {total_bytes}"
        print(f"  ✓ Total bytes processed: {total_bytes}")
        
        await pool.shutdown()
        print("  ✓ File upload worker test passed")
        
    finally:
        temp_file.unlink()


async def test_file_download_worker():
    """Test file download worker"""
    print("\n[TEST 4] Testing file download worker...")
    
    # Create a temporary test file
    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.bin') as f:
        test_data = bytes(range(256)) * 100  # ~25KB of data
        f.write(test_data)
        temp_file = Path(f.name)
    
    try:
        config = WorkerConfig(max_workers=4, worker_type=WorkerType.THREAD)
        pool = WorkerPool(config)
        await pool.start()
        
        download_worker = FileDownloadWorker(pool)
        
        # Stream file with parallel reads
        chunk_size = 1024
        chunks = []
        async for chunk in download_worker.stream_file_parallel(
            temp_file,
            chunk_size=chunk_size,
            num_parallel_reads=4
        ):
            chunks.append(chunk)
        
        # Verify data integrity
        downloaded_data = b''.join(chunks)
        assert downloaded_data == test_data, "Downloaded data doesn't match original"
        print(f"  ✓ File streamed in {len(chunks)} chunks")
        print(f"  ✓ Data integrity verified ({len(downloaded_data)} bytes)")
        
        await pool.shutdown()
        print("  ✓ File download worker test passed")
        
    finally:
        temp_file.unlink()


async def test_worker_pool_metrics():
    """Test worker pool metrics"""
    print("\n[TEST 5] Testing worker pool metrics...")
    
    config = WorkerConfig(max_workers=4, worker_type=WorkerType.THREAD)
    pool = WorkerPool(config)
    await pool.start()
    
    # Submit some tasks
    tasks = [(f"task_{i}", sample_task, (i,), {}) for i in range(20)]
    results = await pool.submit_batch(tasks)
    
    # Get metrics
    metrics = pool.get_metrics()
    
    assert metrics["total_tasks"] == 20
    assert metrics["completed_tasks"] == 20
    assert metrics["failed_tasks"] == 0
    assert metrics["success_rate"] == 100.0
    assert metrics["max_workers"] == 4
    assert metrics["worker_type"] == "thread"
    
    print(f"  ✓ Metrics collected: {metrics}")
    
    await pool.shutdown()
    print("  ✓ Worker pool metrics test passed")


async def main():
    """Run all tests"""
    print("=" * 60)
    print("Worker Pool Module Test Suite")
    print("=" * 60)
    
    start_time = time.time()
    
    try:
        await test_worker_pool_basic()
        await test_worker_pool_batch()
        await test_file_upload_worker()
        await test_file_download_worker()
        await test_worker_pool_metrics()
        
        elapsed = time.time() - start_time
        
        print("\n" + "=" * 60)
        print(f"✓ All tests passed! ({elapsed:.2f}s)")
        print("=" * 60)
        return 0
        
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
