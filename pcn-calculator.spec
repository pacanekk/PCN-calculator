Name:           pcn-calculator
Version:        0.1.0
Release:        1%{?dist}
Summary:        Advanced calculator with modern style

License:        MIT
URL:            https://github.com/pacanekk/PCN-Calculator
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  qt6-rpm-macros
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel

Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative

%description
PCN Calculator is an advanced desktop calculator application
with modern style. Features include:
- Standard and Scientific modes
- Calculation history
- Keyboard support
- Modern dark theme UI built with Qt Quick / QML

%prep
%autosetup

%build
%cmake_qt6
%cmake_build

%install
%cmake_install

%check
%ctest

%files
%{_bindir}/pcn-calculator
%{_datadir}/applications/pcn-calculator.desktop
%{_datadir}/icons/hicolor/256x256/apps/pcn-calculator.png
%doc README.md
%license LICENSE
