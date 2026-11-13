param(
    [int]$Port = 8080,
    [string]$Directory = "C:\Users\HP\OneDrive\Desktop",
    [string]$DefaultFile = "Aroma google.html"
)

if (-not (Test-Path (Join-Path $Directory $DefaultFile))) {
    if (Test-Path (Join-Path $Directory "index.html")) {
        $DefaultFile = "index.html"
    }
}

$mimeTypes = @{
    ".html"  = "text/html; charset=utf-8"
    ".htm"   = "text/html; charset=utf-8"
    ".css"   = "text/css; charset=utf-8"
    ".js"    = "application/javascript; charset=utf-8"
    ".mjs"   = "application/javascript; charset=utf-8"
    ".json"  = "application/json; charset=utf-8"
    ".png"   = "image/png"
    ".jpg"   = "image/jpeg"
    ".jpeg"  = "image/jpeg"
    ".gif"   = "image/gif"
    ".svg"   = "image/svg+xml"
    ".webp"  = "image/webp"
    ".ico"   = "image/x-icon"
    ".woff"  = "font/woff"
    ".woff2" = "font/woff2"
    ".ttf"   = "font/ttf"
    ".otf"   = "font/otf"
    ".mp4"   = "video/mp4"
    ".webm"  = "video/webm"
    ".mp3"   = "audio/mpeg"
    ".wav"   = "audio/wav"
    ".pdf"   = "application/pdf"
    ".txt"   = "text/plain; charset=utf-8"
}

# Bind to localhost
$listener = $null
$actualPort = $Port
for ($i = 0; $i -lt 20; $i++) {
    try {
        $actualPort = $Port + $i
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $actualPort)
        $listener = New-Object System.Net.Sockets.TcpListener $endpoint
        $listener.Start()
        break
    } catch {
        if ($listener -ne $null) {
            try { $listener.Stop() } catch {}
            $listener = $null
        }
        if ($i -eq 19) {
            Write-Error "Could not bind to any port from $Port to $($Port + 19)"
            exit 1
        }
    }
}

$url = "http://localhost:$actualPort/"
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  The Aroma Espresso Bar - Localhost Server is Running!         " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  🌐 Main Website : $url" -ForegroundColor Yellow
Write-Host "  📊 Data Portal  : http://localhost:$actualPort/dataportal  (Pass: 13131313)" -ForegroundColor Magenta
Write-Host "  ⚡ Super Admin  : http://localhost:$actualPort/superadmin  (Pass: 12121212)" -ForegroundColor Red
Write-Host "  Serving file    : $DefaultFile" -ForegroundColor Gray
Write-Host "  Directory       : $Directory" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Opening default browser..." -ForegroundColor DarkGray
Write-Host "  Keep this window open. Press Ctrl+C to stop the server." -ForegroundColor DarkGray
Write-Host ""

# Automatically open default browser
try {
    Start-Process $url -ErrorAction SilentlyContinue
} catch {}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.NoDelay = $true
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 4000
            $stream.WriteTimeout = 4000
            
            $buffer = New-Object byte[] 8192
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -gt 0) {
                $reqText = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                $firstLine = ($reqText -split "(\r?\n)")[0]
                $parts = $firstLine -split ' '
                if ($parts.Length -ge 2) {
                    $method = $parts[0]
                    $rawUrl = $parts[1]
                    
                    # Clean and decode requested path
                    $cleanPath = ($rawUrl -split '[?#]')[0]
                    $decoded = [System.Uri]::UnescapeDataString($cleanPath)
                    
                    $subPath = $decoded.TrimStart('/').Replace('/', '\')
                    $lowerSub = $subPath.ToLower()

                    # Direct routes for Data Portal and Super Admin
                    if ([string]::IsNullOrWhiteSpace($subPath) -or $subPath -eq "index.html" -or $lowerSub -in @("dataportal", "data-portal", "portal", "data", "superadmin", "super-admin", "admin", "super")) {
                        $subPath = $DefaultFile
                    }
                    
                    # Handle favicon gracefully if missing
                    if ($subPath -eq "favicon.ico" -and -not [System.IO.File]::Exists([System.IO.Path]::Combine($Directory, $subPath))) {
                        $header = "HTTP/1.1 204 No Content`r`nConnection: close`r`n`r`n"
                        $hBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
                        $stream.Write($hBytes, 0, $hBytes.Length)
                        $stream.Flush()
                        continue
                    }
                    
                    $targetPath = [System.IO.Path]::Combine($Directory, $subPath)
                    $fullPath = [System.IO.Path]::GetFullPath($targetPath)
                    
                    # If target is a directory, check for default file or index.html inside it
                    if ([System.IO.Directory]::Exists($fullPath)) {
                        $candidate = [System.IO.Path]::Combine($fullPath, $DefaultFile)
                        if ([System.IO.File]::Exists($candidate)) {
                            $fullPath = $candidate
                        } else {
                            $candidate = [System.IO.Path]::Combine($fullPath, "index.html")
                            if ([System.IO.File]::Exists($candidate)) {
                                $fullPath = $candidate
                            }
                        }
                    }
                    
                    if ([System.IO.File]::Exists($fullPath)) {
                        $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
                        $mime = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
                        $fileBytes = [System.IO.File]::ReadAllBytes($fullPath)
                        
                        $header = "HTTP/1.1 200 OK`r`n" +
                                  "Content-Type: $mime`r`n" +
                                  "Content-Length: $($fileBytes.Length)`r`n" +
                                  "Access-Control-Allow-Origin: *`r`n" +
                                  "Cache-Control: no-cache, no-store, must-revalidate`r`n" +
                                  "Connection: close`r`n`r`n"
                        $hBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
                        $stream.Write($hBytes, 0, $hBytes.Length)
                        
                        if ($method -ne "HEAD") {
                            $offset = 0
                            while ($offset -lt $fileBytes.Length) {
                                $chunk = [Math]::Min(65536, $fileBytes.Length - $offset)
                                $stream.Write($fileBytes, $offset, $chunk)
                                $offset += $chunk
                            }
                        }
                        $stream.Flush()
                        Write-Host "[200 OK] $method $rawUrl -> $([System.IO.Path]::GetFileName($fullPath)) ($($fileBytes.Length) bytes)" -ForegroundColor Green
                    } else {
                        $notFound = "404 Not Found: $decoded"
                        $body = [System.Text.Encoding]::UTF8.GetBytes($notFound)
                        $header = "HTTP/1.1 404 Not Found`r`n" +
                                  "Content-Type: text/plain; charset=utf-8`r`n" +
                                  "Content-Length: $($body.Length)`r`n" +
                                  "Connection: close`r`n`r`n"
                        $hBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
                        $stream.Write($hBytes, 0, $hBytes.Length)
                        $stream.Write($body, 0, $body.Length)
                        $stream.Flush()
                        Write-Host "[404 Not Found] $method $rawUrl" -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            # Client disconnected or timeout - safely ignored
        } finally {
            try { $client.Close() } catch {}
        }
    }
} finally {
    if ($listener -ne $null) {
        $listener.Stop()
    }
}
