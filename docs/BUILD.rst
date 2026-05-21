#######################
Build the flashable zip
#######################

..
   SPDX-FileCopyrightText: 2026 ale5000
   SPDX-License-Identifier: GPL-3.0-or-later WITH LicenseRef-Archive-packaging-exception
   SPDX-FileType: DOCUMENTATION

.. contents:: Build methods:
   :local:
   :depth: 1
   :backlinks: none


Prerequisites
=============

All build methods require:

-  **Java 17** — the build toolchain requires Java 17 or later. The CI uses
   the `Eclipse Temurin
   <https://adoptium.net/temurin/releases?version=17&os=any&arch=any>`_ Java
   distribution, which is also recommended locally. If you use `asdf
   <https://asdf-vm.com/>`_, run ``asdf install`` in the project root to
   install the exact version defined in ``.tool-versions``.

-  **Shell** — the main build script (``build.sh``) uses Bash by default, but
   it is written to be compatible with most POSIX-compliant shells; special
   care is taken to ensure BusyBox compatibility. Bash is pre-installed on
   Linux and macOS. On Windows, use ``build.bat`` instead — it invokes
   ``build.sh`` via the bundled BusyBox for Windows (no extra installation
   required).

-  **xmlstarlet** and **unzip** — required only when building with
   ``--arch`` (including ``universal``), to download APKs from F-Droid and
   the microG repository.

Architecture-specific builds
----------------------------

By default the zip uses bundled APKs (mostly ARM). To refresh MicroG and
related apps from F-Droid / microG for a specific device ABI or for all
ABIs in one package, pass ``--arch`` to ``build.sh``:

.. code:: sh

   BUILD_TYPE=full ./build.sh --no-default-build-type --no-pause --arch universal
   BUILD_TYPE=full ./build.sh --no-default-build-type --no-pause --arch x86_64

Or with make:

.. code:: sh

   make buildotauniversal
   make buildota ARGS='--arch x86_64'

Supported values:

-  ``universal`` — Java-only APKs or multi-ABI fat APKs (installer trims
   native libs to the device at flash time). Output filename includes
   ``universal``.
-  ``x86_64``, ``x86``, ``arm64-v8a``, ``armeabi-v7a`` — ABI-filtered APKs
   from the repository indexes.

CI releases
-----------

GitHub Actions builds **all** of the architectures above for each release:

- **Nightly** — on pushes to the default branch (see ``.github/workflows/auto-nightly.yml``):
  updates the ``nightly`` tag and publishes a prerelease with every arch zip.
- **Version** — when a ``v*`` tag is pushed or when the "Tag and release"
  workflow creates one (see ``.github/workflows/auto-release-from-tag.yml``):
  publishes a release with every arch zip. Stable tags require
  ``module.prop`` without a ``-alpha`` suffix.
- **Release candidate** — tags containing ``-rc`` (e.g. ``v1.3.2-rc1``)
  publish a **prerelease** with all arch zips even if ``module.prop`` is still
  ``-alpha``.

Module version (``module.prop``)
--------------------------------

For ``--arch`` builds and CI multi-arch releases, ``tools/generate-module-version.sh``
rewrites ``zip-content/module.prop`` before packaging:

- **Base** — latest **microG Services** (``com.google.android.gms``) version from
  the `microG F-Droid index <https://microg.org/fdroid/repo/>`_ (same source as
  ``pull_arch_apks.sh``).
- **Sub-version** — total git commit count on ``HEAD`` (monotonic; requires a full
  clone, so release workflows use ``fetch-depth: 0``).
- **Suffix** — ``-alpha`` for nightly / RC / local ``keep`` when the tree already
  had ``-alpha``; omitted for stable ``v*`` tags (no ``-rc`` in the tag name).

Example: ``version=v0.3.15.250932.5084-alpha`` with ``versionCode=5084``.

Override the channel with ``MODULE_VERSION_CHANNEL=alpha|stable|keep``. Stable
GitHub releases need a tag like ``v0.3.15.250932.5084`` (no ``-alpha`` in
``module.prop``).
- **Manual nightly tag** — pushing or moving the ``nightly`` tag runs only
  **Auto-release from tag** (not Coverage or Code lint). Use
  ``git push origin HEAD:refs/tags/nightly`` for the tag alone; avoid
  ``git push origin nightly --tags`` if branch ``nightly`` exists, or that
  also triggers branch workflows.

Additional requirements depending on the build method:

-  **make / pdpmake** — for the ``make``, ``buildota``, ``buildotauniversal``,
   and related targets.

-  **Gradle wrapper** — for the ``./gradlew`` build method: no separate
   installation is needed; the wrapper (``gradlew`` / ``gradlew.bat``) included
   in the repository downloads the correct Gradle version automatically.

-  **VS Code** — for the VS Code build method: install `Visual Studio Code
   <https://code.visualstudio.com/>`_.


make / pdpmake
==============

Full flavour
------------

Includes all components (proprietary and open-source):

.. code:: sh

   make buildota

Open-source flavour
-------------------

Includes only open-source components:

.. code:: sh

   make buildotaoss

Test the build
--------------

Run the flashable zip in a simulated Android recovery environment on your PC to
see the results:

.. code:: sh

   make installtest

.. note::

   Run ``buildota`` or ``buildotaoss`` first so that the zip exists in the
   ``output/`` folder.


`Gradle wrapper <https://docs.gradle.org/current/userguide/gradle_wrapper.html>`_
=================================================================================

Full flavour
------------

Includes all components (proprietary and open-source):

.. code:: sh

   ./gradlew buildOta

Open-source flavour
-------------------

Includes only open-source components:

.. code:: sh

   ./gradlew buildOtaOSS

Test the build
--------------

Run the flashable zip in a simulated Android recovery environment on your PC to
see the results:

.. code:: sh

   ./gradlew installTest

.. note::

   Run ``buildOta`` or ``buildOtaOSS`` first so that the zip exists in the
   ``output/`` folder.


VS Code
=======

Full flavour
------------

Includes all components (proprietary and open-source):

Open the project in VS Code and run the ``buildOta`` task.

Open-source flavour
-------------------

Includes only open-source components:

Open the project in VS Code and run the ``buildOtaOSS`` task.

Test the build
--------------

Run the flashable zip in a simulated Android recovery environment on your PC to
see the results:

Open the project in VS Code and run the ``installTest`` task.

.. note::

   Run ``buildOta`` or ``buildOtaOSS`` first so that the zip exists in the
   ``output/`` folder.
