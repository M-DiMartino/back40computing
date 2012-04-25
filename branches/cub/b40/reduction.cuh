/******************************************************************************
 * 
 * Copyright (c) 2011-2012, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2012, NVIDIA CORPORATION.  All rights reserved.
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
 ******************************************************************************/

/******************************************************************************
 * Reduction primitives
 ******************************************************************************/

#pragma once

#include <iterator>
#include <b40/reduction/problem.cuh>
#include <cub/core/operators.cuh>

namespace b40 {


/**
 * @return cudaSuccess on success, error enumeration otherwise
 */
template <
	typename InputIterator,
	typename OutputIterator,
	typename ReductionOp>
cudaError_t Reduce(
	InputIterator 		first,
	OutputIterator 		result,
	int 				num_elements,
	ReductionOp 		reduction_op,
	int 				max_grid_size = 0)
{
	typedef reduction::Problem<
		InputIterator,
		OutputIterator,
		int,
		ReductionOp> ReductionProblem;

	ReductionProblem problem(
		first,
		result,
		num_elements,
		reduction_op,
		max_grid_size);

	return problem.Reduce();
}


/**
 * @return cudaSuccess on success, error enumeration otherwise
 */
template <
	typename InputIterator,
	typename OutputIterator>
cudaError_t Reduce(
	InputIterator 		first,
	OutputIterator 		result,
	int 				num_elements,
	int 				max_grid_size = 0)
{
	typedef typename std::iterator_traits<InputIterator>::value_type T;

	cub::Sum<T> reduction_op;
	return Reduce(first, result, num_elements, reduction_op, max_grid_size);
}


/**
 * @return cudaSuccess on success, error enumeration otherwise
 */
template <
	typename Policy,
	typename InputIterator,
	typename OutputIterator,
	typename ReductionOp>
cudaError_t Reduce(
	Policy 				policy,
	InputIterator 		first,
	OutputIterator 		result,
	int 				num_elements,
	ReductionOp 		reduction_op,
	int 				max_grid_size = 0)
{
	typedef reduction::Problem<
		InputIterator,
		OutputIterator,
		int,
		ReductionOp> ReductionProblem;

	ReductionProblem problem(
		first,
		result,
		num_elements,
		reduction_op,
		max_grid_size);

	return problem.Reduce(policy);
}


}// namespace b40

