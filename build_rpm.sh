#!/bin/bash
# Script to build RPM package for PCN Calculator

set -e
cd "$(dirname "$0")"

VERSION="0.1.0"
NAME="pcn-calculator"
TARBALL="${NAME}-${VERSION}.tar.gz"

echo "=== Building RPM package for ${NAME} v${VERSION} ==="

# Sprawdź czy rpmbuild jest zainstalowane
if ! command -v rpmbuild &> /dev/null; then
    echo "Błąd: rpmbuild nie jest zainstalowane."
    echo "Zainstaluj je: sudo dnf install rpm-build"
    exit 1
fi

# Utwórz strukturę katalogów rpmbuild
echo "Tworzenie struktury katalogów rpmbuild..."
mkdir -p ~/rpmbuild/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

# Copy files to temp directory
TEMP_DIR=$(mktemp -d)
echo "Copying files to ${TEMP_DIR}..."
mkdir -p "${TEMP_DIR}/${NAME}-${VERSION}"
cp -r src tests "${TEMP_DIR}/${NAME}-${VERSION}/"
cp Main.qml CalcButton.qml "${TEMP_DIR}/${NAME}-${VERSION}/"
cp CMakeLists.txt "${TEMP_DIR}/${NAME}-${VERSION}/"
cp icon.png "${TEMP_DIR}/${NAME}-${VERSION}/"
cp pcn-calculator.desktop "${TEMP_DIR}/${NAME}-${VERSION}/"
cp pcn-calculator.spec "${TEMP_DIR}/${NAME}-${VERSION}/"
cp README.md LICENSE "${TEMP_DIR}/${NAME}-${VERSION}/"

# Create tarball
echo "Creating tarball..."
cd "${TEMP_DIR}"
tar czf "${TARBALL}" "${NAME}-${VERSION}"
cp "${TARBALL}" ~/rpmbuild/SOURCES/
cp "${NAME}-${VERSION}/${NAME}.spec" ~/rpmbuild/SPECS/

# Clean temp directory
cd -
rm -rf "${TEMP_DIR}"

# Build RPM
echo "Building RPM package..."
rpmbuild -ba ~/rpmbuild/SPECS/${NAME}.spec

# Find built package
RPM_FILE=$(find ~/rpmbuild/RPMS -name "${NAME}-${VERSION}*.rpm" | head -1)

if [ -n "$RPM_FILE" ]; then
    echo "=== Success! Package built: ${RPM_FILE} ==="
    echo "To install: sudo dnf install ${RPM_FILE}"
    
    # Copy to project directory
    cp "${RPM_FILE}" ./
    echo "Package copied to: $(pwd)/$(basename ${RPM_FILE})"
else
    echo "Error: Built RPM package not found"
    exit 1
fi
