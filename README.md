# zoom-headless-recorder

A reliable Docker-based solution for automated Zoom meeting joining and recording with CLI control.

## Quick Install (One-Line)

```bash
curl -sL https://raw.githubusercontent.com/IamCoder18/zoom-headless-recorder/master/install.sh | bash
```

## Usage

```bash
# Join and record a meeting (with defaults)
zoom-rec run https://zoom.us/j/123456789

# Full custom timing
zoom-rec run https://zoom.us/j/123456789 [password] [duration] [prep] [join] [recordOffset] [leaveOffset] [recordAfter]

# Check status
zoom-rec status

# Interactive scheduling
zoom-rec schedule

# Configure defaults
zoom-rec config
```

## Timing Model

The recorder uses a flexible timing system with these parameters:

| Parameter | Env Variable | Default | Description |
|-----------|--------------|---------|-------------|
| prepBuffer | `ZOOM_PREP_BUFFER` | 60s | System warmup (Xvfb, Zoom ready) before anything |
| joinBuffer | `ZOOM_JOIN_BUFFER` | 300s | Join meeting this many seconds BEFORE scheduled start |
| recordOffset | `ZOOM_RECORD_OFFSET` | 300s | Start recording offset from meeting start (positive = early, negative = after) |
| leaveOffset | `ZOOM_LEAVE_OFFSET` | 0s | Leave meeting relative to end (0 = exact, + = early, - = late) |
| recordAfter | `ZOOM_RECORD_AFTER` | 600s | Keep recording after leaving (captures post-meeting) |

### Example: Meeting at 14:00, duration 60min

With defaults (prep=60, join=300, record=300, leave=0, after=600):
- 13:54: System prep starts (warmup)
- 13:55: Recording starts (recordOffset from 14:00)
- 13:55: Join meeting (joinBuffer before 14:00)
- 14:55: Leave meeting (at scheduled end)
- 15:05: Stop recording (recordAfter 600s)

### Custom Example

```bash
# Join 10min early, start recording 5min early, leave 5min late, record 20min after
zoom-rec run https://zoom.us/j/123 3600 60 600 300 -300 1200
```

## Configuration

Default config (`~/.zoom-recorder/config.json`):
```json
{
  "registry": "ghcr.io",
  "recordingsDir": "~/zoom-recordings",
  "apiPort": 8080,
  "vncPort": 6080,
  "meetingDuration": 3600,
  "prepBuffer": 60,
  "joinBuffer": 300,
  "recordOffset": 300,
  "leaveOffset": 0,
  "recordAfter": 600
}
```

## Access (when recording)

- **noVNC**: http://localhost:6080 (browser-based virtual desktop)
- **API**: http://localhost:8080
- **Recordings**: `~/zoom-recordings/meeting_*.mp4`

## Container Lifecycle

The CLI manages containers intelligently:
1. Starts on demand (via `zoom-rec run`)
2. Follows timing parameters for join/leave/record
3. Auto-stops when done
4. No persistent container = no resource waste

## Legal Note

⚠️ Only use on meetings you host or have explicit permission to record. Automated recording may violate Zoom Terms of Service.

## License

MIT