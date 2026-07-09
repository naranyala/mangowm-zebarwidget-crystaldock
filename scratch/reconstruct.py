import json
import re
import sys

transcript_path = '/home/naranyala/.gemini/antigravity-cli/brain/03aa0a88-3495-4bfd-829b-47e2a996e567/.system_generated/logs/transcript_full.jsonl'

lines = []
with open(transcript_path, 'r') as f:
    for line in f:
        try:
            data = json.loads(line)
            # Find any text that has the file view
            content_str = json.dumps(data)
            if 'Total Bytes: 31055' in content_str:
                # The content might be in some nested tool_responses field
                # Just extract it using regex
                matches = re.findall(r'"output":"(.*?)"', content_str)
                for match in matches:
                    if 'Total Bytes: 31055' in match:
                        content = match.encode('utf-8').decode('unicode_escape')
                        for l in content.split('\\n'):
                            l = l.replace('\\"', '"')
                            if re.match(r'^\d+:', l):
                                original_line = l.split(':', 1)[1]
                                if original_line.startswith(' '):
                                    original_line = original_line[1:]
                                lines.append(original_line)
                        break
                break
        except Exception as e:
            pass

if lines:
    with open('/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/build.zig', 'w') as f:
        f.write('\n'.join(lines))
    print(f'Successfully reconstructed build.zig (part 1) with {len(lines)} lines.')
else:
    print('Failed to find build.zig contents in transcript.')
