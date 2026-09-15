import importlib.util
from pathlib import Path
import unittest
import re

spec = importlib.util.spec_from_file_location('build_data', Path(__file__).resolve().parents[1] / 'scripts/build_data.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = module.SOURCE.read_text()
mock_source = re.sub(r'^:VIDEO_PROVIDER:.*$', ':VIDEO_PROVIDER: placeholder', source, flags=re.M)
mock_source = re.sub(r'^:VIDEO_(?!PROVIDER:)[A-Z_]+:.*\n', '', mock_source, flags=re.M)

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
            module.compile_course(mock_source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: youtube\n:VIDEO_ID: javascript:alert(1)',1))
    def test_vimeo_unlisted_identifier_is_accepted(self):
        course = module.compile_course(mock_source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: vimeo\n:VIDEO_ID: 123456789/abc123',1))
        self.assertEqual(course['tracks'][0]['lessons'][0]['video']['id'], '123456789/abc123')
    def test_video_cue_and_duration_are_preserved(self):
        course = module.compile_course(mock_source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: vimeo\n:VIDEO_ID: 123456789\n:VIDEO_DURATION: 900\n:VIDEO_START: 554',1))
        video = course['tracks'][0]['lessons'][0]['video']
        self.assertEqual((video['start'], video['duration']), (554, 900))
    def test_video_cue_cannot_exceed_duration(self):
        with self.assertRaisesRegex(ValueError, 'hors durée'):
            module.compile_course(mock_source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: vimeo\n:VIDEO_ID: 123456789\n:VIDEO_DURATION: 500\n:VIDEO_START: 554',1))
    def test_video_links_cannot_inject_another_origin(self):
        for link in ['javascript:alert(1)', 'https://vimeo.com.example.org/123', 'https://user:password@vimeo.com/123']:
            with self.subTest(link=link), self.assertRaisesRegex(ValueError, 'Lien vidéo'):
                module.compile_course(mock_source.replace(':VIDEO_PROVIDER: placeholder', ':VIDEO_PROVIDER: vimeo\n:VIDEO_ID: 123456789\n:VIDEO_WATCH_URL: '+link,1))
    def test_unknown_block_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'non pris en charge'):
            module.compile_course(source.replace('#+begin_intro', '#+begin_src',1))
