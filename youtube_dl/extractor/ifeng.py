# coding: utf-8
from __future__ import unicode_literals

from .common import InfoExtractor

from ..utils import (
    ExtractorError,
    unified_strdate,
    int_or_none
)


class IFengIE(InfoExtractor):
    _VALID_URL = r'https?://(?:v\.)?ifeng\.com/c/(?P<id>\S+)'

    _TEST = {
        'url': 'https://v.ifeng.com/c/7xOebkb3cqO',
        'md5': '448df96acb9187f68059f4319c641d9c',
        'info_dict': {
            'id': '7xOebkb3cqO',
            'ext': 'mp4',
            'title': '记者探访北京首例确诊患者“西城大爷” 超强记忆力让人敬佩',
            'upload_date': '20200618',
        }
    }

    def _report_error(self, result):
        if 'message' in result:
            raise ExtractorError('%s said: %s' % (self.IE_NAME, result['message']), expected=True)
        elif 'code' in result:
            raise ExtractorError('%s returns error %d' % (self.IE_NAME, result['code']), expected=True)
        else:
            raise ExtractorError('Can\'t extract Bangumi episode ID')

    def _real_extract(self, url):
        video_id = self._match_id(url)
        webpage = self._download_webpage(url, video_id)

        duration = self._html_search_regex(r'<span class="duration-.+?"><i class="duration_icon-.+?"></i>(.+?)</span>', webpage, 'duration')

        video_url = self._og_search_property('img_video', webpage)

        if not video_url:
            self._report_error(video_url)

        formats = []
        for i in range(19):
            formats.append({
                'url': video_url,
                'ext': video_url[video_url.rfind('.') + 1:],
            })

        return {
            'id': video_id,
            'title': self._og_search_description(webpage),
            'duration': int_or_none(duration),
            'upload_date': unified_strdate(self._og_search_property('time ', webpage)),
            'thumbnail': self._og_search_thumbnail(webpage),
            'formats': formats,
        }
