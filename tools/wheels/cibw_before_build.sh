set -xe

PROJECT_DIR="${1:-$PWD}"
SCIPY_SRC_DIR="${1:-$PWD}/scipy-src"


# Update license
echo "" >> $SCIPY_SRC_DIR/LICENSE.txt
echo "----" >> $SCIPY_SRC_DIR/LICENSE.txt
echo "" >> $SCIPY_SRC_DIR/LICENSE.txt
if [[ $RUNNER_OS == "Linux" ]] ; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_linux.txt >> $SCIPY_SRC_DIR/LICENSE.txt
elif [[ $RUNNER_OS == "macOS" ]]; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_osx.txt >> $SCIPY_SRC_DIR/LICENSE.txt
elif [[ $RUNNER_OS == "Windows" ]]; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_win32.txt >> $SCIPY_SRC_DIR/LICENSE.txt
fi


# further checks to determine if openblas is to be installed
if [[ $(python -c"import sys; print(sys.maxsize)") < $(python -c"import sys; print(2**33)") ]]; then
    echo "No BLAS used for 32-bit wheels"
    export INSTALL_OPENBLAS=false
elif [ -z $INSTALL_OPENBLAS ]; then
    # the macos_arm64 build might not set this variable
    export INSTALL_OPENBLAS=true
fi


# By default, use scipy-openblas32
# On 32-bit platforms and on win-arm64, use scipy-openblas32
OPENBLAS=openblas32

# do we install OpenBLAS as part of the build dependencies?
if [[ "$INSTALL_OPENBLAS" = "true" ]] ; then
    OPENBLAS_GRP="--group ${OPENBLAS}"
else
    OPENBLAS_GRP=""
fi


# install build dependencies via uv
# the lock file lives in this repo, not in the scipy checkout; the check_lock job in
# wheels.yml verifies it still matches scipy's dependency groups
PYTHON_EXE="$(python -c 'import sys; print(sys.executable)')"
uv export --project "$PROJECT_DIR" --no-default-groups --group build --no-emit-project $OPENBLAS_GRP --frozen | \
    uv pip install --python "$PYTHON_EXE" --no-deps --require-hashes -r -


# Configure the pkg-config file for OpenBLAS
if [[ "$INSTALL_OPENBLAS" = "true" ]] ; then
    # The PKG_CONFIG_PATH environment variable will be pointed to this path in
    # cibuildwheel.toml and .github/workflows/wheels.yml. Note that
    # `pkgconf_path` here is only a bash variable local to this file.
    pkgconf_path=$PROJECT_DIR/.openblas
    echo pkgconf_path is $pkgconf_path, OPENBLAS is ${OPENBLAS}
    rm -rf $pkgconf_path
    mkdir -p $pkgconf_path
    python -c "import scipy_${OPENBLAS}; print(scipy_${OPENBLAS}.get_pkg_config())" > $pkgconf_path/scipy-openblas.pc

    # Copy scipy-openblas DLL's to a fixed location so we can point delvewheel
    # at it in `repair_windows.sh` (needed only on Windows because of the lack
    # of RPATH support).
    if [[ $RUNNER_OS == "Windows" ]]; then
        python <<EOF
import os, scipy_${OPENBLAS}, shutil
srcdir = os.path.join(os.path.dirname(scipy_${OPENBLAS}.__file__), "lib")
shutil.copytree(srcdir, os.path.join("$pkgconf_path", "lib"))
EOF
    fi
fi


if [[ $RUNNER_OS == "Windows" ]]; then
    # TODO: include this requirement in a dependency group? At the moment
    # it's the only unpinned package.
    # pkgconf - carries out the role of pkg-config.
    # Alternative is pkgconfiglite that you have to install with choco
    python -m pip install -r $PROJECT_DIR/scipy-src/requirements/pkgconf.txt
fi
