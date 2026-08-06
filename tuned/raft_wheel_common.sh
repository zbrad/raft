#!/bin/bash
# raft_wheel_common.sh — shared helpers for generating per-variant wheel
# build sources without ever modifying git-tracked files. Sourced by
# gb10/rtx40/rtx50's raft_wheel_*.sh scripts.
#
# Design: instead of sed -i'ing pyproject.toml/dependencies.yaml/VERSION
# in place and reverting via a trap on script exit (the previous
# approach -- fragile in practice: an EXIT trap set by a later package's
# build silently *replaces* an earlier one instead of stacking, so one
# package's un-reverted patch leaked into the next package's build;
# sed -i on a symlinked VERSION file destroys the symlink and replaces it
# with a plain file; a crash mid-build left the working tree dirty), each
# package's build source is copied into a per-variant staging directory
# and the variant-specific files are generated fresh there. The
# git-tracked tree is never touched, so there's nothing to revert and no
# way for one variant's (or one package's) build to corrupt another's.

# patch_line_or_fail <file> <sed-pattern> <sed-replacement> <description>
# Applies a single sed substitution and verifies the pattern actually
# matched in the file's CURRENT content (read fresh every call, so this
# "merges" our change onto whatever upstream currently says instead of a
# stale assumption) -- errors loudly instead of silently no-op'ing if the
# pattern is missing, e.g. because upstream changed the line we expected
# to patch.
patch_line_or_fail() {
    local file="$1" pattern="$2" replacement="$3" description="$4"
    # `--` marks end-of-options: several of our patterns start with a
    # literal `-` (e.g. "- libraft-cu13=="), which grep would otherwise
    # try to parse as an option flag and error out on.
    if ! grep -qE -- "${pattern}" "${file}"; then
        echo "ERROR: expected to find pattern for '${description}' in ${file}," \
             "but it's not there -- upstream may have changed. pattern: ${pattern}" >&2
        exit 1
    fi
    sed -i "s/${pattern}/${replacement}/" "${file}"
}

# insert_before_or_fail <file> <anchor_text> <new_content> <description>
# Inserts <new_content> as new line(s) immediately before the first
# occurrence of <anchor_text> (a literal string, not a regex -- unlike
# patch_line_or_fail this is for ADDING lines, not substituting an
# existing one). Verifies the anchor is actually present first, same
# merge-or-error discipline as patch_line_or_fail: errors loudly instead
# of silently doing nothing if upstream restructured the file.
insert_before_or_fail() {
    local file="$1" anchor="$2" new_content="$3" description="$4"
    if ! grep -qF -- "${anchor}" "${file}"; then
        echo "ERROR: expected to find anchor for '${description}' in ${file}," \
             "but it's not there -- upstream may have changed. anchor: ${anchor}" >&2
        exit 1
    fi
    python3 - "${file}" "${anchor}" "${new_content}" <<'PYEOF'
import sys
file, anchor, new_content = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file) as f:
    content = f.read()
content = content.replace(anchor, new_content + "\n" + anchor, 1)
with open(file, "w") as f:
    f.write(content)
PYEOF
}

# remove_yaml_include_or_fail <file> <block_key> <include_name> <description>
# Removes a single "- <include_name>" list item from the `includes:` list
# of the specific top-level dependencies.yaml block named <block_key> --
# NOT just any line matching <include_name> anywhere in the file. The
# same include name is commonly reused across many blocks (e.g.
# depends_on_distributed_ucxx appears both in the top-level conda "all"
# env and in py_run_raft_dask's own wheel-runtime deps); patch_line_or_fail's
# whole-file sed would touch every occurrence, which is wrong here --
# only one specific block's copy should ever be edited. Same merge-or-
# error discipline as the other patch_*_or_fail helpers: verifies both
# the block and the include line are present before removing.
remove_yaml_include_or_fail() {
    local file="$1" block_key="$2" include_name="$3" description="$4"
    python3 - "${file}" "${block_key}" "${include_name}" "${description}" <<'PYEOF'
import sys

file, block_key, include_name, description = sys.argv[1:5]
with open(file) as f:
    lines = f.readlines()


def indent(s):
    return len(s) - len(s.lstrip(" "))


block_start = None
block_indent = None
for i, line in enumerate(lines):
    if line.strip() == f"{block_key}:":
        block_start = i
        block_indent = indent(line)
        break
if block_start is None:
    print(f"ERROR: block '{block_key}' not found in {file} for '{description}'", file=sys.stderr)
    sys.exit(1)

block_end = len(lines)
for i in range(block_start + 1, len(lines)):
    line = lines[i]
    if line.strip() and indent(line) <= block_indent:
        block_end = i
        break

target_idx = None
for i in range(block_start, block_end):
    if lines[i].strip() == f"- {include_name}":
        target_idx = i
        break
if target_idx is None:
    print(
        f"ERROR: include '{include_name}' not found within block '{block_key}' in "
        f"{file} for '{description}' -- upstream may have changed",
        file=sys.stderr,
    )
    sys.exit(1)

del lines[target_idx]
with open(file, "w") as f:
    f.writelines(lines)
PYEOF
}

# add_yaml_include_or_fail <file> <block_key> <include_name> <description>
# Inserts a single "- <include_name>" list item into the `includes:` list
# of the specific top-level dependencies.yaml block named <block_key> --
# the complement of remove_yaml_include_or_fail. Verifies the block and
# its `includes:` key exist and that the include isn't already present,
# same merge-or-error discipline as the other patch_*_or_fail helpers.
add_yaml_include_or_fail() {
    local file="$1" block_key="$2" include_name="$3" description="$4"
    python3 - "${file}" "${block_key}" "${include_name}" "${description}" <<'PYEOF'
import sys

file, block_key, include_name, description = sys.argv[1:5]
with open(file) as f:
    lines = f.readlines()


def indent(s):
    return len(s) - len(s.lstrip(" "))


block_start = None
block_indent = None
for i, line in enumerate(lines):
    if line.strip() == f"{block_key}:":
        block_start = i
        block_indent = indent(line)
        break
if block_start is None:
    print(f"ERROR: block '{block_key}' not found in {file} for '{description}'", file=sys.stderr)
    sys.exit(1)

block_end = len(lines)
includes_idx = None
child_indent = None
for i in range(block_start + 1, len(lines)):
    line = lines[i]
    if line.strip() and indent(line) <= block_indent:
        block_end = i
        break
    if line.strip() == "includes:":
        includes_idx = i
        continue
    if includes_idx is not None and child_indent is None and line.strip().startswith("- "):
        child_indent = indent(line)

if includes_idx is None:
    print(
        f"ERROR: 'includes:' not found within block '{block_key}' in {file} for "
        f"'{description}' -- upstream may have changed",
        file=sys.stderr,
    )
    sys.exit(1)

for i in range(includes_idx, block_end):
    if lines[i].strip() == f"- {include_name}":
        print(
            f"ERROR: include '{include_name}' already present within block '{block_key}' "
            f"in {file} for '{description}'",
            file=sys.stderr,
        )
        sys.exit(1)

indent_str = " " * (child_indent if child_indent is not None else block_indent + 2)
lines.insert(includes_idx + 1, f"{indent_str}- {include_name}\n")
with open(file, "w") as f:
    f.writelines(lines)
PYEOF
}

# stage_package_source <project_root> <pkg_relpath> <staging_root>
# Copies python/<pkg_relpath> (the CURRENT git-tracked source) into
# <staging_root>/python/<pkg_relpath>, a fresh, isolated copy this
# variant's build can freely rewrite. --dereference: several files in
# each package dir (README.md, LICENSE, VERSION) are git-tracked symlinks
# to repo-root siblings (../../README.md etc.) -- a plain `cp -r` copies
# the symlink itself, which then points at a target that doesn't exist in
# the staging tree at all (confirmed: scikit-build-core failed with
# "Readme file not found" on the first version of this without
# --dereference). Dereferencing copies each symlink's actual resolved
# content as a plain file instead, so the staged copy is fully
# self-contained -- no need to separately mirror README.md/LICENSE the
# way dependencies.yaml is mirrored below.
stage_package_source() {
    local project_root="$1" pkg_relpath="$2" staging_root="$3"
    rm -rf "${staging_root:?}/python/${pkg_relpath}"
    mkdir -p "${staging_root}/python"
    cp -r --dereference "${project_root}/python/${pkg_relpath}" "${staging_root}/python/${pkg_relpath}"
    # scikit-build-core's own build/ cache dir (if the real package tree
    # happens to have one lying around from a previous non-staged build)
    # embeds absolute paths in its CMakeCache.txt files at generation
    # time -- blindly copying it into a new location breaks CMake
    # ("directory ... is different than the directory ... where
    # CMakeCache.txt was created", confirmed empirically). Always start
    # the staged copy without one; scikit-build-core regenerates it fresh.
    rm -rf "${staging_root:?}/python/${pkg_relpath}/build"
}

# stage_dependencies_yaml <project_root> <staging_root>
# Copies the CURRENT repo-root dependencies.yaml into
# <staging_root>/dependencies.yaml -- placed at the same relative depth
# from a staged package's pyproject.toml (<staging_root>/python/<pkg>/)
# as the real dependencies.yaml is from the real one, so the package's
# existing `dependencies-file = "../../dependencies.yaml"` reference
# resolves correctly with no path rewriting needed.
stage_dependencies_yaml() {
    local project_root="$1" staging_root="$2"
    cp "${project_root}/dependencies.yaml" "${staging_root}/dependencies.yaml"
}

# stage_repo_root_refs <project_root> <staging_root>
# Each package's CMakeLists.txt reaches outside its own directory via
# relative paths at the SAME depth as dependencies-file above --
# `../../cmake/rapids_config.cmake` and `../../cpp` (confirmed via
# `grep -n '\.\./\.\.' */CMakeLists.txt` across all three packages).
# Unlike pyproject.toml/VERSION/dependencies.yaml, `cmake/` and `cpp/` are
# large, shared, and never need variant-specific content -- CMake only
# ever *reads* through these paths (include()/add_subdirectory()), so a
# symlink (not a copy) is both correct and cheap: no risk of the
# sed-destroys-symlinks class of bug here, since nothing ever writes
# through these paths.
stage_repo_root_refs() {
    local project_root="$1" staging_root="$2"
    ln -sfn "${project_root}/cmake" "${staging_root}/cmake"
    ln -sfn "${project_root}/cpp" "${staging_root}/cpp"
}

# embed_build_info <so_path> <variant> <package> <version> [hw_label]
# Embeds a greppable build-info string into a custom ELF section
# (.raft_build_info) on the given .so -- readable later via
# `readelf -p .raft_build_info <so>`, plain `strings`, or a byte-scan
# (see validate_wheels' check_loaded_variant below). Safe at runtime: a
# custom section with no program-header entry is simply ignored by the
# dynamic loader, same technique already used in raft_build_*.sh's
# archival .so copy.
#
# This is what lets validate_wheels() confirm the ACTUAL library that
# won the site-packages/ install collision (if any) really is this
# variant's build -- not just that the right distribution's RECORD
# metadata got installed. Must be called on the exact .so file that ends
# up staged into the wheel, not a separate archival copy.
#
# hw_label (optional, defaults to the bare variant if omitted) makes the
# binary self-describing about WHICH hardware it targets, not just its
# internal codename -- e.g. "RTX 50-series (Blackwell consumer,
# desktop/laptop, SM 120a)" rather than just "rtx50". Without this, the
# only human-readable description of scope lived in the GitHub release's
# own title text, which goes stale independently of the binary.
embed_build_info() {
    local so_path="$1" variant="$2" package="$3" version="$4" hw_label="${5:-${2}}"
    local tmp
    tmp="$(mktemp)"
    echo "raft-${variant} build: ${package} v${version} (${hw_label}), https://github.com/zbrad/raft, built $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${tmp}"
    # Idempotent: objcopy --add-section on a section name that already
    # exists (e.g. rebuilding without a clean) empirically corrupts its own
    # in-place rewrite ("file format not recognized" on its own temp
    # output) -- strip any prior stamp first. Same fix as zbrad/cuvs's and
    # zbrad/faiss's tuned/env.sh, hit for real running a live verification.
    objcopy --remove-section .raft_build_info "${so_path}" 2>/dev/null || true
    objcopy --add-section .raft_build_info="${tmp}" "${so_path}"
    rm -f "${tmp}"
}

# validate_wheels <dist_dir> <python_version> <variant>
# Installs every wheel in <dist_dir> into a fresh, disposable venv (with
# the RAPIDS nightly index and prereleases allowed -- RAPIDS packages use
# alpha versioning throughout, e.g. ucxx-cu13==0.51.0a48) and exercises
# the actual compiled extension code paths, not just a bare import.
#
# This distinction is exactly what caught the librmm ABI mismatch: a bare
# `import pylibraft` succeeds even when the compiled extension can't
# resolve its symbols -- Python doesn't touch the .so's undefined symbols
# until something actually calls into the code that references them.
# Only `from pylibraft.common.handle import Handle; Handle()` (or
# equivalent) actually loads the extension and would have failed loudly.
# Run this after every wheel build, before publishing.
#
# Collision strategy: libraft/pylibraft/raft-dask genuinely differ per
# GPU architecture (real device code), so their PyPI *distribution* names
# stay variant-suffixed (libraft-rtx50-cu13 etc) -- but the importable
# Python package is left unrenamed ("libraft" in site-packages, not
# "libraft_rtx50"). Renaming the import package too was tried and
# reverted -- it just pushes the identical collision one level up to
# whatever else does `import librmm`. Instead we follow PyTorch's own
# precedent for this exact problem (multiple ABI-incompatible builds --
# CPU/CUDA-11/CUDA-12/ROCm -- of packages that must all import as plain
# `torch`): a dedicated package index per variant, so a resolver is only
# ever offered ONE variant as an install candidate, plus unmodified,
# ordering-based preloading (`import torch` first, pulling in its own
# native libs before anything else can need them). See
# https://pytorch.org/get-started/locally/ (per-CUDA-version index URLs)
# and torch/_C/__init__.py's load-order-dependent native extension init.
#
# librmm/rmm are a separate case: they contain no device code (confirmed
# via `cuobjdump --list-elf`), so they're built ONCE, shared across every
# GPU variant, at PLAIN (unsuffixed) distribution names matching upstream
# -- see raft_wheel_librmm_shared.sh. There's no variant axis to check
# for them here; a version conflict on that shared name is a normal,
# loud pip resolver error, not a silent collision.
#
# Because the "only one variant ever installed" invariant (for
# libraft/pylibraft/raft-dask) lives outside this repo's control (a
# consumer's environment, not our wheel metadata), we can't strictly
# prevent a violation -- only detect it automatically, fast and loudly,
# in two layers:
#   1. Cheap: scan installed distribution metadata for a variant +
#      plain-upstream pair coexisting (the resolver-level precondition
#      failure).
#   2. Authoritative: after the libraries are actually loaded, read back
#      the .raft_build_info marker embed_build_info() wrote into the
#      library that actually won the site-packages/ file collision, and
#      confirm it matches the variant under test -- this is what
#      directly validates "the loaded module is the one we think it is",
#      independent of what any package's metadata claims.
#
# ucxx/libucxx (upstream, not ours -- hard-pin plain rmm-cu13/librmm-cu13
# in their own metadata) are excluded from raft-dask entirely rather than
# accommodated: traced their C++ side and confirmed raft-dask's own
# compiled extensions never actually link against ucxx (see
# raft_wheel_rtx50.sh's raft-dask section), so there was nothing to
# preserve by keeping the dependency.
validate_wheels() {
    local dist_dir="$1" python_version="$2" variant="$3"
    local venv_dir
    venv_dir="$(mktemp -d)/validate-venv"
    echo "Validating wheels in ${dist_dir}..."
    uv venv "${venv_dir}" --python "${python_version}" >&2 || return 1
    uv pip install --python "${venv_dir}/bin/python" \
        --extra-index-url https://pypi.anaconda.org/rapidsai-wheels-nightly/simple \
        --prerelease=allow \
        "${dist_dir}"/*.whl >&2
    if [[ $? -ne 0 ]]; then
        echo "ERROR: wheel install failed -- see output above" >&2
        rm -rf "${venv_dir}"
        return 1
    fi

    "${venv_dir}/bin/python" -c "
import importlib.metadata as md
import re

variant = '${variant}'

# Layer 1 (cheap): fail fast if pip's resolver let both a variant
# distribution and its plain-upstream counterpart into the same
# environment -- the precondition our ordering-based approach requires.
installed = {d.name for d in md.distributions()}
pairs = [
    (f'libraft-{variant}-cu13', 'libraft-cu13'),
    (f'pylibraft-{variant}-cu13', 'pylibraft-cu13'),
    (f'raft-dask-{variant}-cu13', 'raft-dask-cu13'),
]
collisions = [(o, u) for o, u in pairs if o in installed and u in installed]
assert not collisions, (
    f'COLLISION RISK: both a variant and its plain-upstream counterpart '
    f'are installed together: {collisions}. This is exactly what the '
    f'PyTorch-style ordering approach cannot tolerate -- reinstall in an '
    f'isolated environment containing only the {variant} wheels.'
)

import pylibraft
from pylibraft.common.handle import Handle
Handle()
print('pylibraft.common.handle.Handle() instantiated OK -- exercises the compiled extension, not just import')

import raft_dask
from raft_dask.common import Comms
print('raft_dask.common.Comms imported OK')

# Layer 2 (authoritative): confirm the library that actually won the
# site-packages/ file collision (if any) really is this variant's own
# build, by reading the .raft_build_info ELF section embed_build_info()
# wrote into it at wheel-build time -- not just trusting distribution
# metadata, which describes what was *asked* to be installed, not what
# file is actually loaded and running. Only libraft is checked here --
# librmm is shared (unsuffixed, tagged variant='shared' at build time),
# so there's no per-GPU-variant identity to verify for it.
def check_loaded_variant(soname_fragment):
    with open('/proc/self/maps') as f:
        maps = f.read()
    # Anchored on '/' immediately before the fragment so it matches only
    # the BASENAME (e.g. libraft_rtx50_cu133.so) -- a bare substring
    # search also matches unrelated paths like pylibraft/common/cuda.abi3.so
    # (contains \"libraft\" inside \"pylibraft\"), confirmed empirically.
    paths = sorted(set(re.findall(r'(\S*/' + re.escape(soname_fragment) + r'[^/\s]*\.so\S*)', maps)))
    assert paths, f\"no loaded library path matching '{soname_fragment}' found in /proc/self/maps\"
    for p in paths:
        with open(p, 'rb') as bf:
            data = bf.read()
        m = re.search(rb'raft-(\w+) build: (\w+) v', data)
        assert m, f'{p} is loaded but has no embedded raft build-info marker -- not one of our variant builds'
        found = m.group(1).decode()
        assert found == variant, (
            f'COLLISION DETECTED: {p} is loaded, but its build-info marker '
            f\"says variant '{found}', not the expected '{variant}' -- wrong \"
            f'variant won the site-packages/ install collision'
        )
        print(f'OK: {p} confirmed variant={variant}')

check_loaded_variant('libraft')
"
    local result=$?
    rm -rf "${venv_dir}"
    if [[ ${result} -ne 0 ]]; then
        echo "ERROR: wheel validation failed -- see traceback above" >&2
        return 1
    fi
    echo "Wheel validation passed."
    return 0
}
