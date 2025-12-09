#!/usr/bin/env python3
"""
Worker Pool Module for ARBOR

Provides parallel processing capabilities for file uploads and downloads
to significantly increase transfer speeds through concurrent operations.
"""

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional, Any, List, Dict
from enum import Enum
import time

logger = logging.getLogger(__name__)


class WorkerType(Enum):
    """Type of worker pool to use"""
    THREAD = "thread"  # For I/O-bound tasks (file uploads/downloads)
    PROCESS = "process"  # For CPU-bound tasks (compression, hashing)


@dataclass
class WorkerConfig:
    """Configuration for worker pool"""
    max_workers: int = 16
    worker_type: WorkerType = WorkerType.THREAD
    task_timeout: Optional[float] = 300.0  # 5 minutes default timeout
    retry_attempts: int = 3
    retry_delay: float = 1.0  # seconds
    queue_size: int = 1000
    
    
@dataclass
class TaskResult:
    """Result of a worker task"""
    success: bool
    task_id: str
    result: Any = None
    error: Optional[str] = None
    duration: float = 0.0
    retries: int = 0


@dataclass
class TaskMetrics:
    """Metrics for tracking worker pool performance"""
    total_tasks: int = 0
    completed_tasks: int = 0
    failed_tasks: int = 0
    total_bytes_processed: int = 0
    start_time: float = field(default_factory=time.time)
    
    @property
    def success_rate(self) -> float:
        """Calculate success rate as a percentage"""
        if self.total_tasks == 0:
            return 0.0
        return (self.completed_tasks / self.total_tasks) * 100.0
    
    @property
    def elapsed_time(self) -> float:
        """Get elapsed time since start"""
        return time.time() - self.start_time
    
    @property
    def throughput(self) -> float:
        """Calculate throughput in bytes per second"""
        elapsed = self.elapsed_time
        if elapsed <= 0:
            return 0.0
        return self.total_bytes_processed / elapsed


class WorkerPool:
    """
    Worker pool for parallel file processing operations.
    
    Supports both thread-based and process-based workers for different
    types of workloads. Optimized for I/O-bound tasks like file uploads
    and downloads.
    """
    
    def __init__(self, config: Optional[WorkerConfig] = None):
        """
        Initialize worker pool with configuration.
        
        Args:
            config: WorkerConfig instance or None for defaults
        """
        self.config = config or WorkerConfig()
        self._executor: Optional[Any] = None
        self._task_queue: Optional[asyncio.Queue] = None
        self._active_tasks: Dict[str, asyncio.Task] = {}
        self._shutdown = False
        self.metrics = TaskMetrics()
        
        logger.info(
            f"Initializing WorkerPool with {self.config.max_workers} "
            f"{self.config.worker_type.value} workers"
        )
    
    async def start(self):
        """Start the worker pool"""
        if self._executor is not None:
            logger.warning("WorkerPool already started")
            return
        
        # Create task queue (must be done in async context)
        if self._task_queue is None:
            self._task_queue = asyncio.Queue(maxsize=self.config.queue_size)
        
        if self.config.worker_type == WorkerType.THREAD:
            self._executor = ThreadPoolExecutor(max_workers=self.config.max_workers)
        else:
            self._executor = ProcessPoolExecutor(max_workers=self.config.max_workers)
        
        logger.info(f"WorkerPool started with {self.config.max_workers} workers")
    
    async def shutdown(self, wait: bool = True):
        """
        Shutdown the worker pool.
        
        Args:
            wait: Wait for pending tasks to complete
        """
        self._shutdown = True
        
        if wait:
            # Wait for active tasks to complete
            if self._active_tasks:
                logger.info(f"Waiting for {len(self._active_tasks)} active tasks to complete")
                await asyncio.gather(*self._active_tasks.values(), return_exceptions=True)
        
        if self._executor is not None:
            self._executor.shutdown(wait=wait)
            self._executor = None
        
        logger.info("WorkerPool shutdown complete")
    
    async def submit_task(
        self,
        task_id: str,
        func: Callable,
        *args,
        **kwargs
    ) -> TaskResult:
        """
        Submit a task to the worker pool for execution.
        
        Args:
            task_id: Unique identifier for the task
            func: Function to execute
            *args: Positional arguments for the function
            **kwargs: Keyword arguments for the function
            
        Returns:
            TaskResult with execution details
        """
        if self._executor is None:
            await self.start()
        
        if self._shutdown:
            return TaskResult(
                success=False,
                task_id=task_id,
                error="WorkerPool is shutting down"
            )
        
        self.metrics.total_tasks += 1
        start_time = time.time()
        
        # Execute with retry logic
        last_error = None
        for attempt in range(self.config.retry_attempts):
            try:
                # Run the function in the executor
                loop = asyncio.get_event_loop()
                result = await asyncio.wait_for(
                    loop.run_in_executor(self._executor, func, *args, **kwargs),
                    timeout=self.config.task_timeout
                )
                
                duration = time.time() - start_time
                self.metrics.completed_tasks += 1
                
                logger.debug(
                    f"Task {task_id} completed successfully in {duration:.2f}s "
                    f"(attempt {attempt + 1})"
                )
                
                return TaskResult(
                    success=True,
                    task_id=task_id,
                    result=result,
                    duration=duration,
                    retries=attempt
                )
                
            except asyncio.TimeoutError:
                last_error = f"Task timeout after {self.config.task_timeout}s"
                logger.warning(f"Task {task_id} timed out (attempt {attempt + 1})")
                
            except Exception as e:
                last_error = str(e)
                logger.warning(
                    f"Task {task_id} failed (attempt {attempt + 1}): {e}"
                )
            
            # Wait before retry (except on last attempt)
            if attempt < self.config.retry_attempts - 1:
                await asyncio.sleep(self.config.retry_delay * (attempt + 1))
        
        # All retries exhausted
        duration = time.time() - start_time
        self.metrics.failed_tasks += 1
        
        logger.error(f"Task {task_id} failed after {self.config.retry_attempts} attempts")
        
        return TaskResult(
            success=False,
            task_id=task_id,
            error=last_error,
            duration=duration,
            retries=self.config.retry_attempts - 1
        )
    
    async def submit_batch(
        self,
        tasks: List[tuple],
        progress_callback: Optional[Callable] = None
    ) -> List[TaskResult]:
        """
        Submit multiple tasks concurrently.
        
        Args:
            tasks: List of (task_id, func, args, kwargs) tuples
            progress_callback: Optional callback for progress updates
            
        Returns:
            List of TaskResult objects
        """
        if not tasks:
            return []
        
        logger.info(f"Submitting batch of {len(tasks)} tasks")
        
        async def execute_task(task_id, func, args, kwargs):
            result = await self.submit_task(task_id, func, *args, **kwargs)
            if progress_callback:
                await progress_callback(result)
            return result
        
        # Execute all tasks concurrently
        task_coroutines = [
            execute_task(task_id, func, args, kwargs)
            for task_id, func, args, kwargs in tasks
        ]
        
        results = await asyncio.gather(*task_coroutines, return_exceptions=False)
        
        logger.info(
            f"Batch completed: {sum(r.success for r in results)}/{len(results)} successful"
        )
        
        return results
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get current worker pool metrics"""
        return {
            "total_tasks": self.metrics.total_tasks,
            "completed_tasks": self.metrics.completed_tasks,
            "failed_tasks": self.metrics.failed_tasks,
            "active_tasks": len(self._active_tasks),
            "success_rate": self.metrics.success_rate,
            "throughput_bytes_per_sec": self.metrics.throughput,
            "total_bytes_processed": self.metrics.total_bytes_processed,
            "elapsed_time": self.metrics.elapsed_time,
            "max_workers": self.config.max_workers,
            "worker_type": self.config.worker_type.value
        }


class FileUploadWorker:
    """
    Specialized worker for parallel file uploads.
    
    Handles chunked file uploads with integrity verification and
    metadata preservation.
    """
    
    def __init__(self, worker_pool: WorkerPool):
        """
        Initialize file upload worker.
        
        Args:
            worker_pool: WorkerPool instance to use
        """
        self.worker_pool = worker_pool
    
    @staticmethod
    def process_file_chunk(
        file_path: Path,
        chunk_index: int,
        chunk_size: int
    ) -> Dict[str, Any]:
        """
        Process a single file chunk (runs in worker thread).
        
        Args:
            file_path: Path to the file
            chunk_index: Index of the chunk to read
            chunk_size: Size of each chunk in bytes
            
        Returns:
            Dictionary with chunk data and metadata
        """
        import hashlib
        
        offset = chunk_index * chunk_size
        
        with open(file_path, 'rb') as f:
            f.seek(offset)
            chunk_data = f.read(chunk_size)
        
        # Compute checksum for this chunk
        chunk_hash = hashlib.sha256(chunk_data).hexdigest()
        
        return {
            "chunk_index": chunk_index,
            "chunk_data": chunk_data,
            "chunk_size": len(chunk_data),
            "chunk_hash": chunk_hash,
            "offset": offset
        }
    
    async def upload_file_parallel(
        self,
        file_path: Path,
        chunk_size: int = 1024 * 1024,  # 1MB default
        progress_callback: Optional[Callable] = None
    ) -> List[TaskResult]:
        """
        Upload a file using parallel chunk processing.
        
        Args:
            file_path: Path to file to upload
            chunk_size: Size of each chunk in bytes
            progress_callback: Optional progress callback
            
        Returns:
            List of TaskResult for each chunk
        """
        file_size = file_path.stat().st_size
        num_chunks = (file_size + chunk_size - 1) // chunk_size
        
        logger.info(
            f"Starting parallel upload of {file_path.name} "
            f"({file_size} bytes in {num_chunks} chunks)"
        )
        
        # Create tasks for each chunk
        tasks = [
            (
                f"{file_path.name}_chunk_{i}",
                self.process_file_chunk,
                (file_path, i, chunk_size),
                {}
            )
            for i in range(num_chunks)
        ]
        
        # Execute all chunks in parallel
        results = await self.worker_pool.submit_batch(tasks, progress_callback)
        
        # Update metrics
        successful_bytes = sum(
            r.result.get("chunk_size", 0) 
            for r in results 
            if r.success and r.result
        )
        self.worker_pool.metrics.total_bytes_processed += successful_bytes
        
        return results


class FileDownloadWorker:
    """
    Specialized worker for parallel file downloads.
    
    Handles chunked file downloads with range requests and
    parallel streaming support.
    """
    
    def __init__(self, worker_pool: WorkerPool):
        """
        Initialize file download worker.
        
        Args:
            worker_pool: WorkerPool instance to use
        """
        self.worker_pool = worker_pool
    
    @staticmethod
    def read_file_chunk(
        file_path: Path,
        offset: int,
        length: int
    ) -> bytes:
        """
        Read a chunk from a file (runs in worker thread).
        
        Args:
            file_path: Path to the file
            offset: Byte offset to start reading
            length: Number of bytes to read
            
        Returns:
            Chunk data as bytes
        """
        with open(file_path, 'rb') as f:
            f.seek(offset)
            return f.read(length)
    
    async def stream_file_parallel(
        self,
        file_path: Path,
        chunk_size: int = 1024 * 1024,  # 1MB default
        num_parallel_reads: int = 4
    ):
        """
        Stream a file with parallel reads for faster delivery.
        
        Args:
            file_path: Path to file to stream
            chunk_size: Size of each chunk
            num_parallel_reads: Number of chunks to read ahead
            
        Yields:
            File chunks as bytes
        """
        file_size = file_path.stat().st_size
        num_chunks = (file_size + chunk_size - 1) // chunk_size
        
        logger.info(
            f"Starting parallel streaming of {file_path.name} "
            f"({file_size} bytes in {num_chunks} chunks)"
        )
        
        # Pre-load first batch of chunks
        current_chunk = 0
        pending_tasks = {}
        
        while current_chunk < num_chunks:
            # Submit parallel reads
            while (
                len(pending_tasks) < num_parallel_reads and
                current_chunk + len(pending_tasks) < num_chunks
            ):
                chunk_idx = current_chunk + len(pending_tasks)
                offset = chunk_idx * chunk_size
                
                task = asyncio.create_task(
                    self.worker_pool.submit_task(
                        f"{file_path.name}_chunk_{chunk_idx}",
                        self.read_file_chunk,
                        file_path,
                        offset,
                        chunk_size
                    )
                )
                pending_tasks[chunk_idx] = task
            
            # Wait for and yield the next sequential chunk
            if current_chunk in pending_tasks:
                result = await pending_tasks[current_chunk]
                del pending_tasks[current_chunk]
                
                if result.success:
                    chunk_data = result.result
                    self.worker_pool.metrics.total_bytes_processed += len(chunk_data)
                    yield chunk_data
                else:
                    logger.error(f"Failed to read chunk {current_chunk}: {result.error}")
                    raise IOError(f"Failed to read chunk {current_chunk}")
                
                current_chunk += 1


# Convenience functions for easy integration
async def create_upload_worker(max_workers: int = 16) -> FileUploadWorker:
    """
    Create a file upload worker with default configuration.
    
    Args:
        max_workers: Maximum number of concurrent workers
        
    Returns:
        FileUploadWorker instance
    """
    config = WorkerConfig(
        max_workers=max_workers,
        worker_type=WorkerType.THREAD
    )
    pool = WorkerPool(config)
    await pool.start()
    return FileUploadWorker(pool)


async def create_download_worker(max_workers: int = 16) -> FileDownloadWorker:
    """
    Create a file download worker with default configuration.
    
    Args:
        max_workers: Maximum number of concurrent workers
        
    Returns:
        FileDownloadWorker instance
    """
    config = WorkerConfig(
        max_workers=max_workers,
        worker_type=WorkerType.THREAD
    )
    pool = WorkerPool(config)
    await pool.start()
    return FileDownloadWorker(pool)
