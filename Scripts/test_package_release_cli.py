#!/usr/bin/env python3
"""Focused release-artifact regression tests; no Swift compilation required."""
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest

import package_release_cli as packaging


class ReleaseArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.products = self.root / 'products'
        self.products.mkdir()
        self.tools = packaging.tool_names()
        for name in self.tools:
            path = self.products / name
            path.write_bytes(b'fixture executable\n')
            path.chmod(0o755)
        for name in packaging.RESOURCES:
            contents = self.products / name / 'Contents'
            (contents / 'Resources').mkdir(parents=True)
            (contents / 'Info.plist').write_text('fixture plist')
            (contents / 'Resources/data').write_text('fixture resource')
        self.artifacts = self.root / 'artifacts'
        self.archive = self.root / 'release.tar.gz'

    def stage(self, batch, tools):
        packaging.stage(self.products,
            self.artifacts / ('cli-binaries-batch-' + batch) / 'staged-cli.tar', tools)

    def test_complete_batches_preserve_executable_modes_and_all_bundles(self):
        self.stage('1', self.tools[:18])
        self.stage('2', self.tools[18:])
        inventory = packaging.assemble(self.artifacts, self.archive)
        self.assertEqual(inventory['tools'], self.tools)
        self.assertEqual(inventory['resourceBundles'], list(packaging.RESOURCES))
        with tarfile.open(self.archive) as archive:
            self.assertTrue(all(archive.getmember('bin/' + name).mode & 0o111 for name in self.tools))

    def test_missing_bundle_refuses_before_archive_creation(self):
        shutil.rmtree(self.products / packaging.RESOURCES[1])
        self.stage('1', self.tools)
        with self.assertRaisesRegex(ValueError, 'Missing resource bundle'):
            packaging.assemble(self.artifacts, self.archive)
        self.assertFalse(self.archive.exists())

    def test_empty_bundle_resources_refuse(self):
        (self.products / packaging.RESOURCES[1] / 'Contents/Resources/data').unlink()
        self.stage('1', self.tools)
        with self.assertRaisesRegex(ValueError, 'Missing resource bundle'):
            packaging.assemble(self.artifacts, self.archive)

    def test_missing_copy_only_renderer_bundle_refuses(self):
        shutil.rmtree(self.products / 'DICOMKit_DICOMRenderKit.bundle')
        self.stage('1', self.tools)
        with self.assertRaisesRegex(ValueError, 'DICOMKit_DICOMRenderKit.bundle'):
            packaging.assemble(self.artifacts, self.archive)
        self.assertFalse(self.archive.exists())

    def test_missing_batch_tool_refuses(self):
        self.stage('1', self.tools[:-1])
        with self.assertRaisesRegex(ValueError, 'Missing batch executable'):
            packaging.assemble(self.artifacts, self.archive)

    def test_duplicate_batch_tool_refuses(self):
        self.stage('1', self.tools)
        self.stage('2', self.tools[:1])
        with self.assertRaisesRegex(ValueError, 'Duplicate batch executable'):
            packaging.assemble(self.artifacts, self.archive)

    def test_nonexecutable_product_refuses_staging(self):
        (self.products / self.tools[0]).chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'Missing executable'):
            self.stage('1', self.tools)


if __name__ == '__main__':
    unittest.main()
