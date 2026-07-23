#!/bin/bash
# raft_wheel_common.sh — shared helpers for generating per-variant wheel
# build sources without ever modifying git-tracked files. Sourced by
# gb10/rtx40xx/rtx50xx's raft_wheel_*.sh scripts.
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
