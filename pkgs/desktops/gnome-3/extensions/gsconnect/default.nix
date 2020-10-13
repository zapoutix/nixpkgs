{ stdenv
, fetchFromGitHub
, substituteAll
, python3
, openssl
, gsound
, meson
, ninja
, libxml2
, pkgconfig
, gobject-introspection
, wrapGAppsHook
, glib
, gtk3
, at-spi2-core
, upower
, openssh
, gnome3
, gjs
, nixosTests
, atk
, harfbuzz
, pango
, gdk-pixbuf
, gsettings-desktop-schemas
}:

stdenv.mkDerivation rec {
  pname = "gnome-shell-gsconnect";
  version = "43";

  outputs = [ "out" "installedTests" ];

  src = fetchFromGitHub {
    owner = "andyholmes";
    repo = "gnome-shell-extension-gsconnect";
    rev = "v${version}";
    sha256 = "0hm14hg4nhv9hrmjcf9dgm7dsvzpjfifihjmb6yc78y9yjw0i3v7";
  };

  patches = [
    # Make typelibs available in the extension
    (substituteAll {
      src = ./fix-paths.patch;
      gapplication = "${glib.bin}/bin/gapplication";
    })

    # Allow installing installed tests to a separate output
    ./installed-tests-path.patch
  ];

  nativeBuildInputs = [
    meson ninja pkgconfig
    gobject-introspection # for locating typelibs
    wrapGAppsHook # for wrapping daemons
    libxml2 # xmllint
  ];

  buildInputs = [
    glib # libgobject
    gtk3
    at-spi2-core # atspi
    gnome3.nautilus # TODO: this contaminates the package with nautilus and gnome-autoar typelibs but it is only needed for the extension
    gnome3.nautilus-python
    gsound
    upower
    gnome3.caribou
    gjs # for running daemon
    gnome3.evolution-data-server # for libebook-contacts typelib
  ];

  mesonFlags = [
    "-Dgnome_shell_libdir=${gnome3.gnome-shell}/lib"
    "-Dgsettings_schemadir=${glib.makeSchemaPath (placeholder "out") "${pname}-${version}"}"
    "-Dchrome_nmhdir=${placeholder "out"}/etc/opt/chrome/native-messaging-hosts"
    "-Dchromium_nmhdir=${placeholder "out"}/etc/chromium/native-messaging-hosts"
    "-Dopenssl_path=${openssl}/bin/openssl"
    "-Dsshadd_path=${openssh}/bin/ssh-add"
    "-Dsshkeygen_path=${openssh}/bin/ssh-keygen"
    "-Dsession_bus_services_dir=${placeholder "out"}/share/dbus-1/services"
    "-Dpost_install=true"
    "-Dinstalled_test_prefix=${placeholder ''installedTests''}"
  ];

  postPatch = ''
    patchShebangs meson/nmh.sh
    patchShebangs meson/post-install.sh
    patchShebangs installed-tests/prepare-tests.sh

    # TODO: do not include every typelib everywhere
    # for example, we definitely do not need nautilus
    for file in src/extension.js src/prefs.js; do
      substituteInPlace "$file" \
        --subst-var-by typelibPath "$GI_TYPELIB_PATH"
    done
  '';

  postFixup = let
    testDeps = [
      gtk3 harfbuzz atk pango.out gdk-pixbuf
    ];
  in ''
    # Let’s wrap the daemons
    for file in $out/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/service/{daemon,nativeMessagingHost}.js; do
      echo "Wrapping program $file"
      wrapGApp "$file"
    done

    wrapProgram "$installedTests/libexec/installed-tests/gsconnect/minijasmine" \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
      --prefix GI_TYPELIB_PATH : "${stdenv.lib.makeSearchPath "lib/girepository-1.0" testDeps}"
  '';

  uuid = "gsconnect@andyholmes.github.io";

  passthru = {
    tests = {
      installedTests = nixosTests.installed-tests.gsconnect;
    };
  };

  meta = with stdenv.lib; {
    description = "KDE Connect implementation for Gnome Shell";
    homepage = "https://github.com/andyholmes/gnome-shell-extension-gsconnect/wiki";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [ etu ];
    platforms = platforms.linux;
  };
}
