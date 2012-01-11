/******************************************************************************
 * 
 * Copyright 2010-2011 Duane Merrill
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 ******************************************************************************/

/******************************************************************************
 * Upsweep BFS Contraction kernel
 ******************************************************************************/

#pragma once

#include <b40c/util/cta_work_distribution.cuh>
#include <b40c/util/cta_work_progress.cuh>
#include <b40c/util/kernel_runtime_stats.cuh>

#include <b40c/graph/bfs/two_phase/contract_atomic/cta.cuh>

namespace b40c {
namespace graph {
namespace bfs {
namespace two_phase {
namespace contract_atomic {



/**
 * Contraction pass (non-workstealing)
 */
template <typename KernelPolicy, bool WORK_STEALING>
struct SweepPass
{
	static __device__ __forceinline__ void Invoke(
		typename KernelPolicy::VertexId 		&iteration,
		typename KernelPolicy::VertexId 		&queue_index,
		typename KernelPolicy::VertexId 		&steal_index,
		int 									&num_gpus,
		typename KernelPolicy::VertexId 		*&d_edge_frontier,
		typename KernelPolicy::VertexId 		*&d_vertex_frontier,
		typename KernelPolicy::VertexId 		*&d_predecessor,
		typename KernelPolicy::VertexId			*&d_labels,
		typename KernelPolicy::VisitedMask 		*&d_visited_mask,
		util::CtaWorkProgress 					&work_progress,
		util::CtaWorkDistribution<typename KernelPolicy::SizeT> &work_decomposition,
		typename KernelPolicy::SizeT			max_vertex_frontier,
		typename KernelPolicy::SmemStorage		&smem_storage)
	{
		typedef Cta<KernelPolicy> 					Cta;
		typedef typename KernelPolicy::SizeT 		SizeT;

		// Determine our threadblock's work range
		util::CtaWorkLimits<SizeT> work_limits;
		work_decomposition.template GetCtaWorkLimits<
			KernelPolicy::LOG_TILE_ELEMENTS,
			KernelPolicy::LOG_SCHEDULE_GRANULARITY>(work_limits);

		// Return if we have no work to do
		if (!work_limits.elements) {
			return;
		}

		// CTA processing abstraction
		Cta cta(
			iteration,
			queue_index,
			num_gpus,
			smem_storage,
			d_edge_frontier,
			d_vertex_frontier,
			d_predecessor,
			d_labels,
			d_visited_mask,
			work_progress,
			max_vertex_frontier);

		// Process full tiles
		while (work_limits.offset < work_limits.guarded_offset) {

			cta.ProcessTile(work_limits.offset);
			work_limits.offset += KernelPolicy::TILE_ELEMENTS;
		}

		// Clean up last partial tile with guarded-i/o
		if (work_limits.guarded_elements) {
			cta.ProcessTile(
				work_limits.offset,
				work_limits.guarded_elements);
		}
	}
};


/**
 * Atomically steal work from a global work progress construct
 */
template <typename SizeT, typename StealIndex>
__device__ __forceinline__ SizeT StealWork(
	util::CtaWorkProgress &work_progress,
	int count,
	StealIndex steal_index)
{
	__shared__ SizeT s_offset;		// The offset at which this CTA performs tile processing, shared by all

	// Thread zero atomically steals work from the progress counter
	if (threadIdx.x == 0) {
		s_offset = work_progress.Steal<SizeT>(count, steal_index);
	}

	__syncthreads();		// Protect offset

	return s_offset;
}


/**
 * Contraction pass (workstealing)
 */
template <typename KernelPolicy>
struct SweepPass <KernelPolicy, true>
{
	static __device__ __forceinline__ void Invoke(
		typename KernelPolicy::VertexId 		&iteration,
		typename KernelPolicy::VertexId 		&queue_index,
		typename KernelPolicy::VertexId 		&steal_index,
		int 									&num_gpus,
		typename KernelPolicy::VertexId 		*&d_edge_frontier,
		typename KernelPolicy::VertexId 		*&d_vertex_frontier,
		typename KernelPolicy::VertexId 		*&d_predecessor,
		typename KernelPolicy::VertexId			*&d_labels,
		typename KernelPolicy::VisitedMask 		*&d_visited_mask,
		util::CtaWorkProgress 					&work_progress,
		util::CtaWorkDistribution<typename KernelPolicy::SizeT> &work_decomposition,
		typename KernelPolicy::SizeT			max_vertex_frontier,
		typename KernelPolicy::SmemStorage		&smem_storage)
	{
		typedef Cta<KernelPolicy> 					Cta;
		typedef typename KernelPolicy::SizeT 		SizeT;

		// CTA processing abstraction
		Cta cta(
			iteration,
			queue_index,
			num_gpus,
			smem_storage,
			d_edge_frontier,
			d_vertex_frontier,
			d_predecessor,
			d_labels,
			d_visited_mask,
			work_progress,
			max_vertex_frontier);

		// Total number of elements in full tiles
		SizeT unguarded_elements = work_decomposition.num_elements & (~(KernelPolicy::TILE_ELEMENTS - 1));

		// Worksteal full tiles, if any
		SizeT offset;
		while ((offset = StealWork<SizeT>(work_progress, KernelPolicy::TILE_ELEMENTS, steal_index)) < unguarded_elements) {
			cta.ProcessTile(offset);
		}

		// Last CTA does any extra, guarded work (first tile seen)
		if (blockIdx.x == gridDim.x - 1) {
			SizeT guarded_elements = work_decomposition.num_elements - unguarded_elements;
			cta.ProcessTile(unguarded_elements, guarded_elements);
		}
	}
};


/******************************************************************************
 * Contraction Kernel Entrypoint
 ******************************************************************************/

/**
 * Contraction kernel entry point
 */
template <typename KernelPolicy>
__launch_bounds__ (KernelPolicy::THREADS, KernelPolicy::CTA_OCCUPANCY)
__global__
void Kernel(
	typename KernelPolicy::VertexId 		src,						// Source vertex (may be -1 if iteration != 0)
	typename KernelPolicy::VertexId 		iteration,					// Current BFS iteration
	typename KernelPolicy::SizeT			num_elements,				// Number of elements in incoming edge frontier (used when !KernelPolicy::DEQUEUE_PROBLEM_SIZE)
	typename KernelPolicy::VertexId			queue_index,				// Current frontier queue counter index
	typename KernelPolicy::VertexId			steal_index,				// Current workstealing counter index
	int										num_gpus,					// Number of GPUs
	volatile int							*d_done,					// Flag to set when we detect incoming edge frontier is empty
	typename KernelPolicy::VertexId 		*d_edge_frontier,						// Incoming edge frontier
	typename KernelPolicy::VertexId 		*d_vertex_frontier,						// Outgoing vertex frontier
	typename KernelPolicy::VertexId 		*d_predecessor,			// Incoming predecessor edge frontier (used when KernelPolicy::MARK_PREDECESSORS)
	typename KernelPolicy::VertexId			*d_labels,					// BFS labels to set
	typename KernelPolicy::VisitedMask 		*d_visited_mask,			// Mask for detecting visited status
	util::CtaWorkProgress 					work_progress,				// Atomic workstealing and queueing counters
	typename KernelPolicy::SizeT			max_vertex_frontier, 		// Maximum number of elements we can place into the outgoing vertex frontier
	util::KernelRuntimeStats				kernel_stats)				// Kernel timing statistics (used when KernelPolicy::INSTRUMENT)
{
	typedef typename KernelPolicy::SizeT SizeT;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	if (KernelPolicy::INSTRUMENT && (threadIdx.x == 0)) {
		kernel_stats.MarkStart();
	}

	if (iteration == 0) {

		if (threadIdx.x < util::CtaWorkProgress::COUNTERS) {

			// Reset all counters
			work_progress.template Reset<SizeT>();

			// Determine work decomposition for first iteration
			if (threadIdx.x == 0) {

				SizeT num_elements = 0;
				if (src != -1) {

					num_elements = 1;

					// We'll be the only block with active work this iteration.
					// Enqueue the source for us to subsequently process.
					util::io::ModifiedStore<KernelPolicy::WRITE_MODIFIER>::St(src, d_edge_frontier);

					if (KernelPolicy::MARK_PREDECESSORS) {
						// Enqueue predecessor of source
						typename KernelPolicy::VertexId predecessor = -2;
						util::io::ModifiedStore<KernelPolicy::WRITE_MODIFIER>::St(predecessor, d_predecessor);
					}
				}

				// Initialize work decomposition in smem
				smem_storage.state.work_decomposition.template Init<KernelPolicy::LOG_SCHEDULE_GRANULARITY>(
					num_elements, gridDim.x);
			}
		}

		// Barrier to protect work decomposition
		__syncthreads();

		// Don't do workstealing this iteration because without a
		// global barrier after queue-reset, the queue may be inconsistent
		// across CTAs
		SweepPass<KernelPolicy, false>::Invoke(
			iteration,
			queue_index,
			steal_index,
			num_gpus,
			d_edge_frontier,
			d_vertex_frontier,
			d_predecessor,
			d_labels,
			d_visited_mask,
			work_progress,
			smem_storage.state.work_decomposition,
			max_vertex_frontier,
			smem_storage);

	} else {

		// Determine work decomposition
		if (threadIdx.x == 0) {

			// Obtain problem size
			if (KernelPolicy::DEQUEUE_PROBLEM_SIZE) {
				num_elements = work_progress.template LoadQueueLength<SizeT>(queue_index);
			}

			// Signal to host that we're done
			if (num_elements == 0) {
				if (d_done) d_done[0] = 1;
			}

			// Initialize work decomposition in smem
			smem_storage.state.work_decomposition.template Init<KernelPolicy::LOG_SCHEDULE_GRANULARITY>(
				num_elements, gridDim.x);

			// Reset our next outgoing queue counter to zero
			work_progress.template StoreQueueLength<SizeT>(0, queue_index + 2);

			// Reset our next workstealing counter to zero
			work_progress.template PrepResetSteal<SizeT>(steal_index + 1);

		}

		// Barrier to protect work decomposition
		__syncthreads();

		SweepPass<KernelPolicy, KernelPolicy::WORK_STEALING>::Invoke(
			iteration,
			queue_index,
			steal_index,
			num_gpus,
			d_edge_frontier,
			d_vertex_frontier,
			d_predecessor,
			d_labels,
			d_visited_mask,
			work_progress,
			smem_storage.state.work_decomposition,
			max_vertex_frontier,
			smem_storage);
	}

	if (KernelPolicy::INSTRUMENT && (threadIdx.x == 0)) {
		kernel_stats.MarkStop();
		kernel_stats.Flush();
	}
}


} // namespace contract_atomic
} // namespace two_phase
} // namespace bfs
} // namespace graph
} // namespace b40c

