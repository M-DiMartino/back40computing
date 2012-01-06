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
 * BFS partition-contraction problem type
 ******************************************************************************/

#pragma once

#include <b40c/partition/problem_type.cuh>
#include <b40c/util/basic_utils.cuh>
#include <b40c/radix_sort/sort_utils.cuh>

namespace b40c {
namespace graph {
namespace bfs {


/**
 * Type of BFS problem
 */
template <
	typename 	_VertexId,						// Type of signed integer to use as vertex id (e.g., uint32)
	typename 	_SizeT,							// Type of unsigned integer to use for array indexing (e.g., uint32)
	typename 	_VisitedMask,					// Type of unsigned integer to use for visited mask (e.g., uint8)
	typename 	_ValidFlag,						// Type of integer to use for contraction validity (e.g., uint8)
	bool 		_MARK_PREDECESSORS>				// Whether to mark predecessor-vertices (vs. distance-from-source)
struct ProblemType : partition::ProblemType<
	_VertexId, 																	// KeyType
	typename util::If<_MARK_PREDECESSORS, _VertexId, util::NullType>::Type,		// ValueType
	_SizeT>																		// SizeT
{
	typedef _VertexId														VertexId;
	typedef _VisitedMask													VisitedMask;
	typedef _ValidFlag														ValidFlag;
	typedef typename radix_sort::KeyTraits<VertexId>::ConvertedKeyType		UnsignedBits;		// Unsigned type corresponding to VertexId

	static const bool MARK_PREDECESSORS		= _MARK_PREDECESSORS;
	static const _VertexId LOG_MAX_GPUS		= 2;										// The "problem type" currently only reserves space for 4 gpu identities in upper vertex identifier bits
	static const _VertexId MAX_GPUS			= 1 << LOG_MAX_GPUS;

	static const _VertexId GPU_MASK_SHIFT	= (sizeof(_VertexId) * 8) - LOG_MAX_GPUS;
	static const _VertexId GPU_MASK			= (MAX_GPUS - 1) << GPU_MASK_SHIFT;			// Bitmask for masking off the lower vertex id bits to reveal owner gpu id
	static const _VertexId VERTEX_ID_MASK	= ~GPU_MASK;								// Bitmask for masking off the upper control bits in vertex identifiers
};


} // namespace bfs
} // namespace graph
} // namespace b40c

