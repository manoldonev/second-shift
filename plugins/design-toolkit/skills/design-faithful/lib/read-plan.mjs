// design-faithful — pure read-path limit logic.
//
// DesignSync is a model-invoked tool, so the actual list_projects/get_project/list_files/
// get_file calls are made by the orchestrating agent — the design-faithful skills, which
// carry the DesignSync tool. (The Workflow engine does NOT call DesignSync; its runtime has
// no tool access — see design-sync.mjs READ BOUNDARY.) These helpers are
// pure: they take the JSON those calls return and apply the limits / fail-closed
// classification, so the contract is testable without the live tool.
//
// DesignSync read limits: get_file is capped at 256 KiB (returns truncated:true past the cap);
// write/delete batches are capped at 256 per call; a PROJECT_TYPE_PROJECT handoff bundle is
// opened BY PROJECT ID (list_projects is design-system-only and never lists it).

import { FAIL_CLOSED, FailClosedError, PROJECT_TYPES } from './contract-types.mjs'

/** DesignSync per-call batch ceiling (write_files/delete_files ≤256/call). */
export const BATCH_LIMIT = 256
/** get_file size cap, bytes (256 KiB). Informational — truncation is reported by the tool. */
export const FILE_BYTE_LIMIT = 256 * 1024

/**
 * Partition the paths from a list_files result into ≤BATCH_LIMIT batches and surface the
 * project type. Throws FailClosedError(batch-overflow) if asked to plan a single batch
 * larger than the ceiling.
 *
 * @param {{paths:string[]}} listFilesResult the get-from-DesignSync list_files payload
 * @param {{projectType?:string, batchSize?:number}} [opts]
 * @returns {{batches:string[][], projectType:string|undefined, total:number}}
 */
export function planFetch(listFilesResult, opts = {}) {
  const paths = (listFilesResult && Array.isArray(listFilesResult.paths)) ? listFilesResult.paths : []
  const batchSize = opts.batchSize == null ? BATCH_LIMIT : opts.batchSize
  if (batchSize > BATCH_LIMIT) {
    throw new FailClosedError(FAIL_CLOSED.BATCH_OVERFLOW, `requested batchSize ${batchSize} > ${BATCH_LIMIT}`)
  }
  const batches = []
  for (let i = 0; i < paths.length; i += batchSize) batches.push(paths.slice(i, i + batchSize))
  return { batches, projectType: opts.projectType, total: paths.length }
}

/**
 * Classify a get_file result. Returns the sanitizable content on success; throws a
 * FailClosedError on a truncated (oversized) file or an unreachable/error result.
 *
 * @param {{content?:string, truncated?:boolean, error?:unknown}|null|undefined} getFileResult
 * @param {string} [path] for the error detail
 * @returns {{path:string|undefined, content:string}}
 */
export function classifyFetchResult(getFileResult, path) {
  if (getFileResult == null || getFileResult.error != null) {
    throw new FailClosedError(FAIL_CLOSED.SOURCE_UNREACHABLE, path)
  }
  if (getFileResult.truncated === true) {
    throw new FailClosedError(FAIL_CLOSED.FILE_TOO_LARGE, path)
  }
  return { path, content: typeof getFileResult.content === 'string' ? getFileResult.content : '' }
}

/**
 * Assert the project's actual type matches what the caller expected. Throws
 * FailClosedError(project-type-mismatch) otherwise. Returns the validated type.
 *
 * @param {{type?:string}|null|undefined} getProjectResult
 * @param {string} expectedType one of PROJECT_TYPES
 * @returns {string}
 */
export function assertProjectType(getProjectResult, expectedType) {
  const actual = getProjectResult && getProjectResult.type
  const known = Object.values(PROJECT_TYPES)
  if (!known.includes(expectedType)) {
    throw new FailClosedError(FAIL_CLOSED.PROJECT_TYPE_MISMATCH, `unknown expected type ${expectedType}`)
  }
  if (actual !== expectedType) {
    throw new FailClosedError(FAIL_CLOSED.PROJECT_TYPE_MISMATCH, `expected ${expectedType}, got ${actual ?? 'undefined'}`)
  }
  return actual
}
