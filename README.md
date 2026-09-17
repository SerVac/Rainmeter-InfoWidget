# Rainmeter InfoWidget Balance

A compact Rainmeter skin that fetches a single value from an HTTP JSON API and displays it with color-coded thresholds.

## Requirements

- Windows
- [Rainmeter](https://www.rainmeter.net/) 4.x or newer
- PowerShell 5.1 (used via the bundled `RunCommand` plugin)

## Install

1. Copy the `infoVidget/Balance` folder into your Rainmeter `Skins` folder
   (usually `%USERPROFILE%\Documents\Rainmeter\Skins`).
2. Right-click the Rainmeter tray icon, then **Refresh all**.
3. Load `infoVidget\Balance\Balance.ini`.

## Configuration

Edit `@Resources/settings.txt` and then **click the widget** to reload.

| Key   | Description                                                        |
| ----- | ------------------------------------------------------------------ |
| `url` | API endpoint                                                       |
| `json`| JSON path to display, e.g. `data.balance` or `items[0].name`       |
| `err` | JSON path to a numeric error code (`0` = OK); leave empty to disable |

### Examples

```
# Simple nested value
url=https://api.example.com/account
json=data.balance
err=code
```

```
# Array element
url=https://api.example.com/items
json=items[0].name
err=
```

```
# Whole response / bare value
url=https://api.example.com/status
json=
err=code
```

```
# No auth, no error field
url=https://api.example.com/uptime
json=uptime
err=
```

### Authentication

`@Resources/token.txt` is optional. It accepts either a raw token
(sent as `Bearer <token>`) or an explicit prefix:

```
Bearer eyJhbGciOi...
```

```
Basic dXNlcjpwYXNz
```

The `Bearer` / `Basic` prefix is detected case-insensitively; surrounding
whitespace and quotes are trimmed. Leave the file empty for no authentication.

## Controls

- **Refresh chip** — left-click cycles to the next interval (1 / 5 / 15 / 30 min), right-click to the previous.
- **G / Y chips** — left/right-click adjust green and yellow thresholds.
- **Font chip** — left/right-click change the value font size.
- **Settings chip** — opens `settings.txt` in Notepad.
- Clicking the background refetches immediately.

## Color states

- **Gray** — no data.
- **Green / Yellow / Red** — numeric value relative to the `Yellow` and `Green` thresholds.
- **Blue** — non-numeric value.
- **Blinking red / orange** — request or API error.

## Logs

Activity is written to `@Resources/balance.log`. Typical error values:
`ERR:401`, `ERR:403`, `ERR:HTTP:<code>`, `ERR:TIMEOUT`, `ERR:NET:dns`,
`ERR:NET:tls`, `ERR:API:<code>`, `ERR:API:no-field`.

## License

MIT — see [LICENSE](LICENSE).
