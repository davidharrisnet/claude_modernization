# report: builds the Word EXPORT report (MigrationExportReport.docx, with charts) from source-metadata.json only.
# This tool verifies nothing against a target, so this is an export report, not a verification report (that is import-postgresql's).
# No Word installation needed: charts are drawn with System.Drawing and the OpenXML package is written directly. Deterministic:
# the same metadata always produces the same bytes (fixed zip order and timestamps, fixed chart geometry, run date from the JSON).
# The helpers below build the OpenXML package and the charts.

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression

$script:RC = @{
    Source = [System.Drawing.ColorTranslator]::FromHtml('#2563EB')
    Target = [System.Drawing.ColorTranslator]::FromHtml('#F59E0B')
    Pass   = [System.Drawing.ColorTranslator]::FromHtml('#15803D')
    Fail   = [System.Drawing.ColorTranslator]::FromHtml('#B91C1C')
    Ink    = [System.Drawing.ColorTranslator]::FromHtml('#1F2937')
    Muted  = [System.Drawing.ColorTranslator]::FromHtml('#6B7280')
    Grid   = [System.Drawing.ColorTranslator]::FromHtml('#E5E7EB')
    Soft   = [System.Drawing.ColorTranslator]::FromHtml('#F3F4F6')
}

# ------------------------------------------------------------------ chart drawing

function New-Canvas([int]$W, [int]$H) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)
    return [pscustomobject]@{ Bmp = $bmp; G = $g }
}

function ConvertTo-PngBytes($Canvas) {
    $ms = New-Object System.IO.MemoryStream
    $Canvas.Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose(); $Canvas.G.Dispose(); $Canvas.Bmp.Dispose()
    return , $bytes
}

function New-Font([single]$Size, [bool]$Bold) {
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return New-Object System.Drawing.Font('Segoe UI', $Size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Get-NiceMax([double]$Max) {
    if ($Max -le 0) { return 1 }
    $pow = [Math]::Pow(10, [Math]::Floor([Math]::Log10($Max)))
    foreach ($m in 1, 2, 2.5, 5, 10) { if ($Max -le $m * $pow) { return $m * $pow } }
    return 10 * $pow
}

# Grouped (or single-series) vertical bar chart.
function New-BarChartPng([string]$Title, [string[]]$Labels, [double[]]$A, [double[]]$B, [string]$NameA, [string]$NameB, [int]$W = 1300, [int]$H = 520) {
    $cv = New-Canvas $W $H
    $g = $cv.G
    $ink = New-Object System.Drawing.SolidBrush $script:RC.Ink
    $muted = New-Object System.Drawing.SolidBrush $script:RC.Muted
    $gridPen = New-Object System.Drawing.Pen($script:RC.Grid, 1)
    $g.DrawString($Title, (New-Font 26 $true), $ink, 30, 18)

    $left = 90; $right = 40; $top = 100; $bottom = 110
    $pw = $W - $left - $right; $ph = $H - $top - $bottom
    $vals = @($A) + $(if ($B) { @($B) } else { @() })
    $max = Get-NiceMax (($vals | Measure-Object -Maximum).Maximum)
    $small = New-Font 18 $false

    for ($i = 0; $i -le 5; $i++) {
        $y = $top + $ph - ($ph * $i / 5)
        $g.DrawLine($gridPen, $left, $y, $left + $pw, $y)
        $lbl = [string]([Math]::Round($max * $i / 5, 1))
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = [System.Drawing.StringAlignment]::Far
        $g.DrawString($lbl, $small, $muted, (New-Object System.Drawing.RectangleF(0, ($y - 11), ($left - 10), 24)), $sf)
    }
    # legend, right-aligned, spacing from measured text widths
    $wA = $g.MeasureString($NameA, $small).Width
    $wB = if ($B) { $g.MeasureString($NameB, $small).Width } else { 0 }
    $total = 26 + $wA + $(if ($B) { 30 + 26 + $wB } else { 0 })
    $lx = $W - $right - $total
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $script:RC.Source), [single]$lx, 26, 18, 18)
    $g.DrawString($NameA, $small, $ink, [single]($lx + 26), 22)
    if ($B) {
        $bx = $lx + 26 + $wA + 30
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $script:RC.Target), [single]$bx, 26, 18, 18)
        $g.DrawString($NameB, $small, $ink, [single]($bx + 26), 22)
    }

    $n = $Labels.Count
    $slot = $pw / [Math]::Max($n, 1)
    $series = if ($B) { 2 } else { 1 }
    $barW = [Math]::Min(70, ($slot * 0.7) / $series)
    $center = New-Object System.Drawing.StringFormat; $center.Alignment = [System.Drawing.StringAlignment]::Center
    $valFont = New-Font 17 $true
    for ($i = 0; $i -lt $n; $i++) {
        $cx = $left + $slot * ($i + 0.5)
        $groupW = $barW * $series
        for ($s = 0; $s -lt $series; $s++) {
            $v = if ($s -eq 0) { $A[$i] } else { $B[$i] }
            $bh = $ph * $v / $max
            $x = $cx - $groupW / 2 + $barW * $s
            $color = if ($s -eq 0) { $script:RC.Source } else { $script:RC.Target }
            if ($bh -gt 0) { $g.FillRectangle((New-Object System.Drawing.SolidBrush $color), [single]$x, [single]($top + $ph - $bh), [single]($barW - 3), [single]$bh) }
            $g.DrawString([string]$v, $valFont, $ink, (New-Object System.Drawing.RectangleF([single]($x - 12), [single]($top + $ph - $bh - 24), [single]($barW + 21), 24)), $center)
        }
        $g.DrawString($Labels[$i], $small, $ink, (New-Object System.Drawing.RectangleF([single]($cx - $slot / 2 + 2), [single]($top + $ph + 10), [single]($slot - 4), 80)), $center)
    }
    $g.DrawLine((New-Object System.Drawing.Pen($script:RC.Muted, 2)), $left, ($top + $ph), ($left + $pw), ($top + $ph))
    return ConvertTo-PngBytes $cv
}

# ------------------------------------------------------------------ OpenXML building blocks

function Xe([string]$s) {
    if ($null -eq $s) { return '' }
    $clean = [regex]::Replace($s, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    return [System.Security.SecurityElement]::Escape($clean)
}

function Rn([string]$Text, [bool]$Bold = $false, [string]$Color = $null, [int]$Size = 0, [bool]$Italic = $false) {
    $rpr = ''
    if ($Bold) { $rpr += '<w:b/>' }
    if ($Italic) { $rpr += '<w:i/>' }
    if ($Color) { $rpr += "<w:color w:val=""$Color""/>" }
    if ($Size -gt 0) { $rpr += "<w:sz w:val=""$Size""/><w:szCs w:val=""$Size""/>" }
    if ($rpr) { $rpr = "<w:rPr>$rpr</w:rPr>" }
    $parts = (Xe $Text) -split "`n"
    $body = ($parts | ForEach-Object { "<w:t xml:space=""preserve"">$_</w:t>" }) -join '<w:br/>'
    return "<w:r>$rpr$body</w:r>"
}

function Pg([string]$Runs, [string]$Style = '', [string]$Align = '', [bool]$KeepNext = $false, [int]$After = -1) {
    $ppr = ''
    if ($Style) { $ppr += "<w:pStyle w:val=""$Style""/>" }
    if ($KeepNext) { $ppr += '<w:keepNext/>' }
    if ($Style -eq 'Heading1' -and $script:BreakNext) { $ppr += '<w:pageBreakBefore/>'; $script:BreakNext = $false }
    if ($After -ge 0) { $ppr += "<w:spacing w:after=""$After""/>" }
    if ($Align) { $ppr += "<w:jc w:val=""$Align""/>" }
    if ($ppr) { $ppr = "<w:pPr>$ppr</w:pPr>" }
    return "<w:p>$ppr$Runs</w:p>"
}

function PT([string]$Text, [string]$Style = '') { return (Pg (Rn $Text) $Style) }
function Bullet([string]$Text) { return (Pg (Rn $Text) 'ListBullet') }
# A page break is applied to the next Heading1 as pageBreakBefore (a standalone break paragraph can create blank pages).
function PageBreak { $script:BreakNext = $true; return '' }

# Table cell helper. $Fill/$Color hex without '#'.
function Tcell([string]$Text, [int]$Width, [string]$Fill = '', [string]$Color = '', [bool]$Bold = $false, [string]$Align = '') {
    $tcpr = "<w:tcW w:w=""$Width"" w:type=""dxa""/>"
    if ($Fill) { $tcpr += "<w:shd w:val=""clear"" w:color=""auto"" w:fill=""$Fill""/>" }
    $tcpr += '<w:vAlign w:val="center"/>'
    return "<w:tc><w:tcPr>$tcpr</w:tcPr>$(Pg (Rn $Text $Bold $Color) 'TableText' $Align)</w:tc>"
}

# Generic table. $Header = string[]; $Rows = array of arrays of cell specs (string or @{Text;Fill;Color;Bold;Align}).
function Table([int[]]$Widths, [string[]]$Header, $Rows) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<w:tbl><w:tblPr><w:tblW w:w="' + (($Widths | Measure-Object -Sum).Sum) + '" w:type="dxa"/><w:tblBorders>')
    foreach ($b in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') { [void]$sb.Append("<w:$b w:val=""single"" w:sz=""4"" w:space=""0"" w:color=""D1D5DB""/>") }
    [void]$sb.Append('</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="90" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
    foreach ($w in $Widths) { [void]$sb.Append("<w:gridCol w:w=""$w""/>") }
    [void]$sb.Append('</w:tblGrid><w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>')
    for ($i = 0; $i -lt $Header.Count; $i++) { [void]$sb.Append((Tcell $Header[$i] $Widths[$i] '1F3864' 'FFFFFF' $true)) }
    [void]$sb.Append('</w:tr>')
    foreach ($row in $Rows) {
        [void]$sb.Append('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
        for ($i = 0; $i -lt $row.Count; $i++) {
            $c = $row[$i]
            if ($c -is [hashtable]) { [void]$sb.Append((Tcell ([string]$c.Text) $Widths[$i] ([string]$c.Fill) ([string]$c.Color) ([bool]$c.Bold) ([string]$c.Align))) }
            else { [void]$sb.Append((Tcell ([string]$c) $Widths[$i])) }
        }
        [void]$sb.Append('</w:tr>')
    }
    [void]$sb.Append('</w:tbl>')
    return $sb.ToString() + (Pg '' 'Small')
}

function ResultCell([bool]$Passed) {
    if ($Passed) { return @{ Text = 'PASS'; Fill = 'DCFCE7'; Color = '15803D'; Bold = $true; Align = 'center' } }
    return @{ Text = 'FAIL'; Fill = 'FEE2E2'; Color = 'B91C1C'; Bold = $true; Align = 'center' }
}

function Banner([bool]$Passed, [string]$Headline, [string]$Sub) {
    $fill = if ($Passed) { '15803D' } else { 'B91C1C' }
    return "<w:tbl><w:tblPr><w:tblW w:w=""9360"" w:type=""dxa""/><w:tblLayout w:type=""fixed""/><w:tblCellMar><w:top w:w=""160"" w:type=""dxa""/><w:left w:w=""200"" w:type=""dxa""/><w:bottom w:w=""160"" w:type=""dxa""/><w:right w:w=""200"" w:type=""dxa""/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w=""9360""/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=""9360"" w:type=""dxa""/><w:shd w:val=""clear"" w:color=""auto"" w:fill=""$fill""/></w:tcPr>$(Pg (Rn $Headline $true 'FFFFFF' 44) '' 'center' $false 40)$(Pg (Rn $Sub $false 'FFFFFF' 24) '' 'center' $false 0)</w:tc></w:tr></w:tbl>" + (Pg '' 'Small')
}

function Image($Images, [byte[]]$Png, [string]$Alt, [int]$WidthEmu = 5943600) {
    $bmpStream = New-Object System.IO.MemoryStream(, $Png)
    $img = [System.Drawing.Image]::FromStream($bmpStream)
    $cx = $WidthEmu
    $cy = [int64]($WidthEmu * $img.Height / $img.Width)
    $img.Dispose(); $bmpStream.Dispose()
    $n = $Images.Items.Count + 1
    [void]$Images.Items.Add([pscustomobject]@{ Name = "image$n.png"; RId = "rIdImg$n"; Bytes = $Png })
    $alt = Xe $Alt
    $drawing = "<w:drawing><wp:inline distT=""0"" distB=""0"" distL=""0"" distR=""0""><wp:extent cx=""$cx"" cy=""$cy""/><wp:docPr id=""$n"" name=""Chart $n"" descr=""$alt""/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=""1""/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri=""http://schemas.openxmlformats.org/drawingml/2006/picture""><pic:pic><pic:nvPicPr><pic:cNvPr id=""$n"" name=""image$n.png"" descr=""$alt""/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=""rIdImg$n""/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=""0"" y=""0""/><a:ext cx=""$cx"" cy=""$cy""/></a:xfrm><a:prstGeom prst=""rect""><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>"
    return (Pg "<w:r>$drawing</w:r>" 'Figure' 'center')
}

# ------------------------------------------------------------------ static package parts

function Get-StylesXml {
    $s = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    $s += '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    $s += '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="1200" w:after="120"/></w:pPr><w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="64"/><w:szCs w:val="64"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="360"/></w:pPr><w:rPr><w:color w:val="4B5563"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="2563EB"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Small"><w:name w:val="Small"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="60"/></w:pPr><w:rPr><w:sz w:val="12"/><w:szCs w:val="12"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Figure"><w:name w:val="Figure"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="120"/></w:pPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="200"/></w:pPr><w:rPr><w:i/><w:color w:val="6B7280"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr><w:spacing w:after="60"/></w:pPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F3F4F6"/><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="200"/></w:pPr><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:color w:val="6B7280"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:color w:val="6B7280"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '</w:styles>'
    return $s
}

function Get-NumberingXml {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="540" w:hanging="270"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/></w:rPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
}

$script:Ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"'

# Human-readable form of a 'a|b|c' answer row (fractional seconds trimmed for display only).
function Format-Answer([string]$Row) {
    $r = [regex]::Replace($Row, '(\d{2}:\d{2}:\d{2})\.\d+', '$1')
    $parts = $r -split '\|'
    if ($parts.Count -eq 2) { return "$($parts[0]) = $($parts[1])" }
    return ($parts -join ' | ')
}

function Write-ZipEntry($Zip, [string]$Name, [byte[]]$Bytes, [DateTimeOffset]$Stamp) {
    $e = $Zip.CreateEntry($Name, [System.IO.Compression.CompressionLevel]::Optimal)
    $e.LastWriteTime = $Stamp
    $s = $e.Open()
    try { $s.Write($Bytes, 0, $Bytes.Length) } finally { $s.Dispose() }
}

function Save-Docx([string]$Path, [string]$BodyXml, $Images, [string]$Footer, [string]$Created, [string]$HeaderText = 'MasterAntiqueRepair - Database Migration Verification', [string]$DocTitle = 'Database Migration Verification Report') {
    $stamp = New-Object DateTimeOffset(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $enc = $script:Utf8NoBom
    $hdr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    $sect = '<w:sectPr><w:headerReference w:type="default" r:id="rIdHdr"/><w:footerReference w:type="default" r:id="rIdFtr"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1300" w:right="1440" w:bottom="1200" w:left="1440" w:header="600" w:footer="500" w:gutter="0"/></w:sectPr>'
    $document = "$hdr<w:document $($script:Ns)><w:body>$BodyXml$sect</w:body></w:document>"
    $header = "$hdr<w:hdr $($script:Ns)>$(Pg (Rn $HeaderText) 'Header' 'right')</w:hdr>"
    $footer = "$hdr<w:ftr $($script:Ns)><w:p><w:pPr><w:pStyle w:val=""Footer""/><w:jc w:val=""center""/></w:pPr>$(Rn ($Footer + '   |   Page '))<w:r><w:fldChar w:fldCharType=""begin""/></w:r><w:r><w:instrText xml:space=""preserve""> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType=""separate""/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=""end""/></w:r></w:p></w:ftr>"
    $ct = "$hdr<Types xmlns=""http://schemas.openxmlformats.org/package/2006/content-types""><Default Extension=""rels"" ContentType=""application/vnd.openxmlformats-package.relationships+xml""/><Default Extension=""xml"" ContentType=""application/xml""/><Default Extension=""png"" ContentType=""image/png""/><Override PartName=""/word/document.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml""/><Override PartName=""/word/styles.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml""/><Override PartName=""/word/numbering.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml""/><Override PartName=""/word/header1.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml""/><Override PartName=""/word/footer1.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml""/><Override PartName=""/docProps/core.xml"" ContentType=""application/vnd.openxmlformats-package.core-properties+xml""/><Override PartName=""/docProps/app.xml"" ContentType=""application/vnd.openxmlformats-officedocument.extended-properties+xml""/></Types>"
    $rels = "$hdr<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships""><Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"" Target=""word/document.xml""/><Relationship Id=""rId2"" Type=""http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"" Target=""docProps/core.xml""/><Relationship Id=""rId3"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties"" Target=""docProps/app.xml""/></Relationships>"
    $docRels = New-Object System.Text.StringBuilder
    [void]$docRels.Append("$hdr<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">")
    [void]$docRels.Append('<Relationship Id="rIdSty" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>')
    [void]$docRels.Append('<Relationship Id="rIdNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>')
    [void]$docRels.Append('<Relationship Id="rIdHdr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>')
    [void]$docRels.Append('<Relationship Id="rIdFtr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>')
    foreach ($im in $Images.Items) { [void]$docRels.Append("<Relationship Id=""$($im.RId)"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"" Target=""media/$($im.Name)""/>") }
    [void]$docRels.Append('</Relationships>')
    $core = "$hdr<cp:coreProperties xmlns:cp=""http://schemas.openxmlformats.org/package/2006/metadata/core-properties"" xmlns:dc=""http://purl.org/dc/elements/1.1/"" xmlns:dcterms=""http://purl.org/dc/terms/"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""><dc:title>$(Xe $DocTitle)</dc:title><dc:creator>dbmigrate</dc:creator><dcterms:created xsi:type=""dcterms:W3CDTF"">$Created</dcterms:created><dcterms:modified xsi:type=""dcterms:W3CDTF"">$Created</dcterms:modified></cp:coreProperties>"
    $app = "$hdr<Properties xmlns=""http://schemas.openxmlformats.org/officeDocument/2006/extended-properties""><Application>dbmigrate</Application></Properties>"

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    if (Test-Path $Path) { Remove-Item $Path -Force }
    $fs = [System.IO.File]::Create($Path)
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Write-ZipEntry $zip '[Content_Types].xml' $enc.GetBytes($ct) $stamp
        Write-ZipEntry $zip '_rels/.rels' $enc.GetBytes($rels) $stamp
        Write-ZipEntry $zip 'docProps/core.xml' $enc.GetBytes($core) $stamp
        Write-ZipEntry $zip 'docProps/app.xml' $enc.GetBytes($app) $stamp
        Write-ZipEntry $zip 'word/document.xml' $enc.GetBytes($document) $stamp
        Write-ZipEntry $zip 'word/_rels/document.xml.rels' $enc.GetBytes($docRels.ToString()) $stamp
        Write-ZipEntry $zip 'word/styles.xml' $enc.GetBytes((Get-StylesXml)) $stamp
        Write-ZipEntry $zip 'word/numbering.xml' $enc.GetBytes((Get-NumberingXml)) $stamp
        Write-ZipEntry $zip 'word/header1.xml' $enc.GetBytes($header) $stamp
        Write-ZipEntry $zip 'word/footer1.xml' $enc.GetBytes($footer) $stamp
        foreach ($im in $Images.Items) { Write-ZipEntry $zip "word/media/$($im.Name)" $im.Bytes $stamp }
    } finally { $zip.Dispose(); $fs.Dispose() }
}

