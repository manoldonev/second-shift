// design-faithful — delta-only sync planner (push direction).
//
// Pure, dependency-free. Computes what to write/delete to converge a Claude Design design-system
// project onto the locally-emitted card set, WITHOUT a wholesale replace. This is the delta basis
// idempotency requires: re-running with an unchanged source must produce an empty
// `writes` array (there is no readable remote manifest to diff against, so the diff is byte-for-byte
// over the components/*/index.html contents the caller fetched + sanitized).
//
// The caller (an interactive DesignSync session — see PUSH.md) feeds:
//   local  — the freshly emitted file set: { path, content }[]   (from buildDesignSystem)
//   remote — the project's current files: { path, content }[]    (list_files + get_file + sanitize)
// On a cold start (no project yet, or create_project just minted an empty one) `remote` is absent
// or [] → every local file is a write, nothing is deleted.

const COMPONENTS_PREFIX = 'components/'

/** Normalize a {path,content}[] (absent → empty) into a Map<path, content>. */
function toMap(files) {
  const map = new Map()
  for (const f of files || []) {
    if (f && typeof f.path === 'string') map.set(f.path, f.content)
  }
  return map
}

/**
 * Compute the convergence delta between the emitted local set and the project's current state.
 *
 * @param {{local: {path:string,content:string}[],
 *          remote?: {path:string,content:string}[]}} input  (remote absent ⇒ cold start)
 * @returns {{writes: {path:string,content:string}[], deletes: string[], unchanged: string[]}}
 *   - writes    — new or byte-changed local files (the only paths to write_files)
 *   - deletes   — remote `components/**` paths absent from local (stale cards to delete_files);
 *                 NON-components paths (e.g. a render-artifact _ds_manifest.json) are never deleted
 *   - unchanged — local paths whose bytes already match remote (the no-op set; empty `writes`
 *                 on a clean re-run means every local path landed here)
 */
export function planSync(input) {
  const local = toMap(input && input.local)
  const remote = toMap(input && input.remote)

  const writes = []
  const unchanged = []
  for (const [path, content] of local) {
    if (remote.has(path) && remote.get(path) === content) {
      unchanged.push(path)
    } else {
      writes.push({ path, content })
    }
  }

  const deletes = []
  for (const path of remote.keys()) {
    if (path.startsWith(COMPONENTS_PREFIX) && !local.has(path)) deletes.push(path)
  }

  return { writes, deletes, unchanged }
}
