import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('build_data', Path(__file__).resolve().parents[1] / 'scripts/build_data.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = module.SOURCE.read_text()

class EditorialSourceTests(unittest.TestCase):
    def test_duplicate_identity_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'dupliqué'):
            module.compile_course(source.replace(':CUSTOM_ID: nommer-frais', ':CUSTOM_ID: nommer-temoins'))
    def test_bad_correct_option_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Choix incohérents'):
            module.compile_course(source.replace(':ANSWERS: non', ':ANSWERS: absent', 1))
    def test_unclosed_block_is_rejected(self):
        with self.assertRaises(ValueError):
            module.compile_course(source.rsplit('#+end_takeaway',1)[0])
    def test_video_identifier_is_checked(self):
        with self.assertRaisesRegex(ValueError, 'YouTube'):
            module.compile_course(source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: youtube\n:VIDEO_ID: javascript:alert(1)',1))
    def test_vimeo_unlisted_identifier_is_accepted(self):
        course = module.compile_course(source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: vimeo\n:VIDEO_ID: 123456789/abc123',1))
        self.assertEqual(course['tracks'][0]['lessons'][0]['video']['id'], '123456789/abc123')
    def test_unknown_block_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'non pris en charge'):
            module.compile_course(source.replace('#+begin_intro', '#+begin_src',1))
