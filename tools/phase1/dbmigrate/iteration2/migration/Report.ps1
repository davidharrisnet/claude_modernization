# report: builds a stakeholder-ready Word document (.docx, with charts) from verification-results.json.
# No Word installation needed: charts are drawn with System.Drawing and the OpenXML package is written
# directly. Deterministic: the same results JSON always produces the same bytes (fixed zip order and
# timestamps, fixed chart geometry, run date taken from the JSON rather than the clock).

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

function New-DonutChartPng([int]$Passed, [int]$Total, [string]$Caption) {
    $cv = New-Canvas 620 520
    $g = $cv.G
    $ink = New-Object System.Drawing.SolidBrush $script:RC.Ink
    $muted = New-Object System.Drawing.SolidBrush $script:RC.Muted
    $g.DrawString('Check outcome', (New-Font 26 $true), $ink, 30, 18)
    # the pen is centred on the path, so the ring's outer edge is the rectangle inflated by half the thickness
    $rect = New-Object System.Drawing.Rectangle(140, 140, 340, 340)
    $failed = $Total - $Passed
    $thick = 60
    $penG = New-Object System.Drawing.Pen($script:RC.Pass, $thick)
    $penR = New-Object System.Drawing.Pen($script:RC.Fail, $thick)
    if ($Total -eq 0) {
        $g.DrawEllipse((New-Object System.Drawing.Pen($script:RC.Grid, $thick)), $rect)
    } elseif ($failed -eq 0) {
        $g.DrawEllipse($penG, $rect)
    } elseif ($Passed -eq 0) {
        $g.DrawEllipse($penR, $rect)
    } else {
        $sweepG = 360.0 * $Passed / $Total
        $g.DrawArc($penG, $rect, -90, [single]$sweepG)
        $g.DrawArc($penR, $rect, [single](-90 + $sweepG), [single](360 - $sweepG))
    }
    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = [System.Drawing.StringAlignment]::Center; $center.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString("$Passed / $Total", (New-Font 54 $true), $ink, (New-Object System.Drawing.RectangleF(110, 250, 400, 70)), $center)
    $g.DrawString($Caption, (New-Font 22 $false), $muted, (New-Object System.Drawing.RectangleF(110, 320, 400, 40)), $center)
    return ConvertTo-PngBytes $cv
}

# Rows = tables, columns = evidence types, each cell PASS/FAIL.
function New-StatusGridPng($Tables) {
    $rowH = 52; $labelW = 250; $colW = 230
    $cols = @('Row count', 'Row content', 'Row hash')
    $W = $labelW + $colW * $cols.Count + 40
    $H = 110 + $rowH * $Tables.Count + 20
    $cv = New-Canvas $W $H
    $g = $cv.G
    $ink = New-Object System.Drawing.SolidBrush $script:RC.Ink
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.DrawString('Verification status by table', (New-Font 26 $true), $ink, 30, 18)
    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = [System.Drawing.StringAlignment]::Center; $center.LineAlignment = [System.Drawing.StringAlignment]::Center
    $f = New-Font 20 $true
    for ($c = 0; $c -lt $cols.Count; $c++) {
        $g.DrawString($cols[$c], $f, $ink, (New-Object System.Drawing.RectangleF(($labelW + $colW * $c), 70, $colW, 36)), $center)
    }
    for ($r = 0; $r -lt $Tables.Count; $r++) {
        $t = $Tables[$r]
        $y = 110 + $rowH * $r
        $g.DrawString($t.Name, (New-Font 20 $false), $ink, 30, ($y + 12))
        $flags = @($t.CountPassed, $t.ContentPassed, ($t.SourceHash -eq $t.TargetHash))
        for ($c = 0; $c -lt 3; $c++) {
            $color = if ($flags[$c]) { $script:RC.Pass } else { $script:RC.Fail }
            $box = New-Object System.Drawing.RectangleF(($labelW + $colW * $c + 6), ($y + 4), ($colW - 12), ($rowH - 8))
            $g.FillRectangle((New-Object System.Drawing.SolidBrush $color), $box)
            $g.DrawString($(if ($flags[$c]) { 'PASS' } else { 'FAIL' }), $f, $white, $box, $center)
        }
    }
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

# ------------------------------------------------------------------ report content

function Get-Rows($Domain, [string]$Name) {
    $d = $Domain | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $pairs = @()
    foreach ($r in @($d.SourceRows)) { $p = ([string]$r) -split '\|'; $pairs += , @($p[0], [double]$p[1]) }
    $tpairs = @()
    foreach ($r in @($d.TargetRows)) { $p = ([string]$r) -split '\|'; $tpairs += , @($p[0], [double]$p[1]) }
    return [pscustomobject]@{ Source = $pairs; Target = $tpairs; Passed = $d.Passed }
}

# Human-readable form of a 'a|b|c' answer row (fractional seconds trimmed for display only).
function Format-Answer([string]$Row) {
    $r = [regex]::Replace($Row, '(\d{2}:\d{2}:\d{2})\.\d+', '$1')
    $parts = $r -split '\|'
    if ($parts.Count -eq 2) { return "$($parts[0]) = $($parts[1])" }
    return ($parts -join ' | ')
}

function New-DomainChart($Domain, [string]$Name, [string]$Title, [string]$LabelPrefix, [string]$TargetName) {
    $rows = Get-Rows $Domain $Name
    $labels = @($rows.Source | ForEach-Object { "$LabelPrefix$($_[0])" })
    $a = [double[]]@($rows.Source | ForEach-Object { $_[1] })
    $b = [double[]]@(foreach ($s in $rows.Source) { $m = @($rows.Target | Where-Object { $_[0] -eq $s[0] }); if ($m.Count -gt 0) { $m[0][1] } else { 0 } })
    return New-BarChartPng $Title $labels $a $b 'SQL Server' $TargetName 1300 460
}

function Build-ReportDocument($R, $SelfTest, $Images) {
    $script:BreakNext = $false
    $tn = if ($R.Meta.TargetName) { [string]$R.Meta.TargetName } else { 'SQLite' }
    $loc = [string]$R.Meta.TargetLocation
    if ($loc -match '[\\/]') { $loc = Split-Path -Leaf $loc }
    $m = $R.Meta; $s = $R.Summary
    $passed = [bool]$R.Passed
    $tables = @($R.Tables); $checks = @($R.Checks); $domain = @($R.Domain)
    $verdictWord = if ($passed) { 'PASSED' } else { 'FAILED' }
    $selfOk = if ($SelfTest) { [bool]$SelfTest.Passed } else { $null }
    $b = New-Object System.Text.StringBuilder
    $add = { param($x) [void]$b.Append($x) }

    # ---- title page
    & $add (Pg (Rn 'Database Migration Verification Report') 'Title')
    & $add (Pg (Rn "MasterAntiqueRepair: SQL Server to $tn") 'Subtitle')
    if ($m.Iteration) { & $add (Pg (Rn "Iteration $($m.Iteration)$(if ($m.IterationTitle) { ' - ' + $m.IterationTitle })" $true '2563EB' 28) '' '' $false 200) }
    & $add (Banner $passed "VERIFICATION $verdictWord" "$($s.ChecksPassed) of $($s.ChecksTotal) checks passed  |  $($s.RowsVerifiedIdentical) of $($s.RowsSource) rows verified identical  |  $($s.Tables) tables")
    & $add (Pg (Rn "Run date (UTC): $($m.RunTimeUtc)") '' '' $false 40)
    & $add (Pg (Rn "Source: $($m.SourceServer), database $($m.SourceDatabase)") '' '' $false 40)
    & $add (Pg (Rn "Target: $tn $loc, $($m.TargetClient)") '' '' $false 40)
    & $add (Pg (Rn "Tooling version: git commit $($m.GitCommit)") '' '' $false 240)
    & $add (Pg (Rn 'Contents' $true '1F3864' 28) '' '' $false 60)
    foreach ($item in '1. Executive summary', '2. Scope and method', '3. Results at a glance', '4. Data verification in detail', '5. Schema and integrity', '6. Business-level summaries', '7. Behaviour tests and tooling self-test', '8. Differences found', '9. Intentional exclusions and known differences', '10. Reproducibility', '11. Sign-off', 'Appendix A. Full row hashes') { & $add (Pg (Rn $item) '' '' $false 20) }
    & $add (PageBreak)

    # ---- 1 executive summary
    & $add (PT '1. Executive summary' 'Heading1')
    if ($passed) {
        & $add (PT "The MasterAntiqueRepair SQL Server database was exported and loaded into a new $tn database. Every check passed. All $($s.RowsSource) rows across $($s.Tables) tables in the source were found in the $tn copy with identical content, the schema objects (tables, columns, keys, foreign keys, indexes) match, and the database rules that the application depends on still work in the copy.")
    } else {
        & $add (PT "The MasterAntiqueRepair SQL Server database was exported and loaded into a new $tn database, but verification found differences. $($s.ChecksPassed) of $($s.ChecksTotal) checks passed and $($s.RowsVerifiedIdentical) of $($s.RowsSource) source rows were verified identical. The differences are itemised in section 8.")
    }
    & $add (PT 'Everything in this report was produced by a deterministic script, not by a language model: the same source database always produces the same export files, and the same verification results always produce the same report.')
    & $add (Table @(3120, 2080, 2080, 2080) @('Measure', 'Source (SQL Server)', "Target ($tn)", 'Result') @(
        , @('Tables', "$($s.Tables)", "$($s.Tables)", (ResultCell (@($checks | Where-Object { $_.Name -eq 'Tables' -and $_.Passed }).Count -eq 1)))
        , @('Rows in all tables', "$($s.RowsSource)", "$(($tables | Measure-Object -Property TargetRows -Sum).Sum)", (ResultCell ($s.RowsSource -eq ($tables | Measure-Object -Property TargetRows -Sum).Sum)))
        , @('Rows verified identical, field by field', "$($s.RowsSource)", "$($s.RowsVerifiedIdentical)", (ResultCell ($s.RowsVerifiedIdentical -eq $s.RowsSource)))
        , @('Checks passed', "$($s.ChecksTotal)", "$($s.ChecksPassed)", (ResultCell ($s.ChecksPassed -eq $s.ChecksTotal)))
    ))

    # ---- 2 scope and method
    & $add (PT '2. Scope and method' 'Heading1')
    & $add (PT 'What was migrated' 'Heading2')
    & $add (PT "All application tables in the source database: $((($tables | ForEach-Object { $_.Name }) -join ', ')). The table structure, primary keys, foreign keys (including cascade rules), indexes (including the filtered unique index that lets a deleted user's name be reused), default values, auto-increment counters and every row of data were carried across. The Entity Framework bookkeeping table (__MigrationHistory) was intentionally not migrated.")
    & $add (PT 'How it was checked' 'Heading2')
    & $add (Bullet 'Row counts: every table is counted in both databases and compared.')
    & $add (Bullet 'Row content: every value of every row is read from both databases, converted to one common text form, and compared field by field. NULL is distinguished from an empty string, and the way each value is stored (integer, text, binary) is checked too. Special characters, line breaks, quotes and emoji are covered.')
    & $add (Bullet 'Fingerprints: for each table a SHA-256 hash of all rows is computed on each side. Two identical hashes mean the two sets of rows are identical; any single changed character produces a different hash.')
    & $add (Bullet "Schema objects: the structure of the $tn database is read back and compared with the structure expected from the SQL Server catalog.")
    & $add (Bullet 'Business summaries: the same query is run on both databases (users by type, tickets by state, and so on) and the answers compared.')
    & $add (Bullet 'Behaviour tests: rules such as unique active usernames, foreign keys and identity counters are exercised on a throw-away copy of the new database.')
    & $add (Bullet "Self-test of the tooling: a second export must be byte-identical to the first, $tn's own tooling (sqldiff for SQLite, CHECKSUM TABLE for MySQL) must find no differences between two independently loaded copies, and a deliberately damaged copy must be caught and pinpointed.")

    # ---- 3 results at a glance
    & $add (PageBreak)
    & $add (PT '3. Results at a glance' 'Heading1')
    & $add (Image $Images (New-DonutChartPng ([int]$s.ChecksPassed) ([int]$s.ChecksTotal) 'checks passed') "Donut chart: $($s.ChecksPassed) of $($s.ChecksTotal) checks passed" 2300000)
    & $add (Pg (Rn "Figure 1. Overall outcome of all $($s.ChecksTotal) checks." $false $null 0 $true) 'Caption' 'center')
    $labels = [string[]]@($tables | ForEach-Object { $_.Name })
    & $add (Image $Images (New-BarChartPng 'Rows per table' $labels ([double[]]@($tables | ForEach-Object { $_.SourceRows })) ([double[]]@($tables | ForEach-Object { $_.TargetRows })) 'SQL Server' $tn) "Grouped bar chart of row counts per table, SQL Server versus $tn" 5300000)
    & $add (Pg (Rn 'Figure 2. Row count of every table in the source and in the new database.' $false $null 0 $true) 'Caption' 'center')
    & $add (Image $Images (New-StatusGridPng $tables) 'Status grid: pass or fail per table for row count, row content and row hash' 4000000)
    & $add (Pg (Rn 'Figure 3. Verification status of each table.' $false $null 0 $true) 'Caption' 'center')

    # ---- 4 data detail
    & $add (PageBreak)
    & $add (PT '4. Data verification in detail' 'Heading1')
    $rows = foreach ($t in $tables) {
        , @($t.Name, "$($t.SourceRows)", "$($t.TargetRows)", "$($t.TargetRows - $t.SourceRows)", "$($t.RowsIdentical)", (ResultCell ($t.CountPassed -and $t.ContentPassed)), $t.SourceHash.Substring(0, 16))
    }
    & $add (Table @(1500, 950, 950, 700, 1100, 1000, 3160) @('Table', 'Source rows', 'Target rows', 'Diff', 'Rows identical', 'Result', 'Row hash (SHA-256, first 16)') $rows)
    & $add (Pg (Rn 'The hash is computed over all rows of the table in a fixed order. Source and target hashes matched for every table marked PASS; full hashes are listed in Appendix A.' $false $null 0 $true) 'Caption')

    # ---- 5 schema
    & $add (PT '5. Schema and integrity' 'Heading1')
    $schema = @($checks | Where-Object { $_.Category -eq 'Schema' -and $null -ne $_.Source })
    $short = { param($n) $i = $n.IndexOf(' ('); if ($i -gt 0) { $n.Substring(0, $i) } else { $n } }
    & $add (Image $Images (New-BarChartPng 'Schema objects compared' ([string[]]@($schema | ForEach-Object { & $short $_.Name })) ([double[]]@($schema | ForEach-Object { $_.Source })) ([double[]]@($schema | ForEach-Object { $_.Target })) 'Expected from SQL Server' "Found in $tn" 1300 500) 'Grouped bar chart of schema object counts, expected versus found' 5300000)
    & $add (Pg (Rn "Figure 4. Number of schema objects of each kind, expected from the SQL Server catalog versus found in $tn." $false $null 0 $true) 'Caption' 'center')
    $srows = foreach ($c in @($checks | Where-Object { $_.Category -in 'Schema', 'Integrity' })) {
        , @($c.Name, $(if ($null -ne $c.Source) { "$($c.Source)" } else { '-' }), $(if ($null -ne $c.Target) { "$($c.Target)" } else { '-' }), (ResultCell ([bool]$c.Passed)))
    }
    & $add (Table @(5160, 1300, 1300, 1600) @('Check', 'Expected', 'Found', 'Result') $srows)

    # ---- 6 business summaries
    & $add (PageBreak)
    & $add (PT '6. Business-level summaries' 'Heading1')
    & $add (PT 'The same question was asked of both databases; the answers must match exactly. The charts below show the answers side by side.')
    & $add (Image $Images (New-DomainChart $domain 'Users by type' 'Users by type' '' $tn) "Bar chart: users by type, SQL Server versus $tn")
    & $add (Image $Images (New-DomainChart $domain 'Users per role' 'Users per role' '' $tn) "Bar chart: users per role, SQL Server versus $tn")
    & $add (Image $Images (New-DomainChart $domain 'Users active vs soft-deleted' 'Active and soft-deleted users' '' $tn) 'Bar chart: active versus soft-deleted users')
    & $add (Image $Images (New-DomainChart $domain 'Tickets by state' 'Tickets by state' 'State ' $tn) 'Bar chart: tickets by state')
    & $add (Image $Images (New-DomainChart $domain 'Audit events by action' 'Audit events by action' 'Action ' $tn) 'Bar chart: audit events by action')
    $drows = foreach ($d in $domain) {
        $ans = (@($d.SourceRows) | Select-Object -First 4 | ForEach-Object { Format-Answer $_ }) -join '; '
        if (@($d.SourceRows).Count -gt 4) { $ans += '; ...' }
        , @($d.Name, $ans, (ResultCell ([bool]$d.Passed)))
    }
    & $add (Table @(3300, 4660, 1400) @('Summary', 'Answer (source; identical in target when PASS)', 'Result') $drows)

    # ---- 7 behaviour + selftest
    & $add (PageBreak)
    & $add (PT '7. Behaviour tests and tooling self-test' 'Heading1')
    & $add (PT 'Behaviour tests were run on a throw-away copy of the new database, so the delivered database was never modified.')
    $brows = foreach ($c in @($checks | Where-Object { $_.Category -eq 'Behaviour' })) { , @($c.Name, (ResultCell ([bool]$c.Passed))) }
    & $add (Table @(7760, 1600) @('Behaviour', 'Result') $brows)
    if ($SelfTest) {
        & $add (PT 'Self-test of the migration tooling' 'Heading2')
        $trows = foreach ($t in @($SelfTest.Tests)) { , @($t.Category, $t.Name, (ResultCell ([bool]$t.Passed))) }
        & $add (Table @(1500, 6260, 1600) @('Area', 'Test', 'Result') $trows)
    } else {
        & $add (PT "The tooling self-test has not been run for this report (run: dbmigrate selftest --target $($m.Target)).")
    }

    # ---- 8 differences
    & $add (PT '8. Differences found' 'Heading1')
    $diffRows = New-Object System.Collections.ArrayList
    foreach ($t in $tables) { foreach ($mm in @($t.Mismatches)) { [void]$diffRows.Add(@($mm.Table, $mm.Key, $mm.Column, $mm.Source, $mm.Target)) } }
    foreach ($c in @($checks | Where-Object { -not $_.Passed })) { [void]$diffRows.Add(@($c.Category, $c.Name, '-', '-', $c.Detail)) }
    foreach ($d in @($domain | Where-Object { -not $_.Passed })) { [void]$diffRows.Add(@('Summary', $d.Name, '-', ((@($d.SourceRows) | ForEach-Object { Format-Answer $_ }) -join '; '), ((@($d.TargetRows) | ForEach-Object { Format-Answer $_ }) -join '; '))) }
    if ($diffRows.Count -eq 0) {
        & $add (Pg (Rn 'None. No differences were found between the source and the target.' $true '15803D'))
    } else {
        & $add (PT "$($diffRows.Count) difference(s) found (credential columns are redacted):")
        & $add (Table @(1300, 2100, 1300, 2330, 2330) @('Table / area', 'Row / check', 'Column', 'Source', 'Target') @($diffRows | ForEach-Object { , @($_) }))
    }

    # ---- 9 exclusions
    & $add (PT '9. Intentional exclusions and known differences' 'Heading1')
    & $add (Bullet "The Entity Framework migration history table (__MigrationHistory) is not migrated; it only describes the SQL Server schema history and has no meaning in $tn.")
    & $add (Bullet 'The SQL Server "dbo" schema prefix is dropped. Table and column names keep their exact spelling and case.')
    foreach ($kd in @($m.KnownDifferences)) { & $add (Bullet ([string]$kd)) }
    & $add (Bullet 'The single user table keeps its "Discriminator" column (Customer / Employee / Manager) unchanged.')
    if ($m.SanitizeCredentials) {
        & $add (Bullet "Every migrated Users row had its password hash and security stamp set to NULL, with a new MustResetPassword column set to 1 - a deliberate one-time-bootstrap policy: forcing a password reset on next login means no usable legacy credential needs to be carried into the target at all. Verification confirms every row is sanitized (section 7) and that every other Users column is unchanged from the source.")
    } else {
        & $add (Bullet "Password hashes and security stamps were copied byte-for-byte. They are compared during verification but never printed in this report. The exported SQL files and the $tn database therefore contain credential-equivalent data and must be protected accordingly.")
    }

    # ---- 10 reproducibility
    & $add (PT '10. Reproducibility' 'Heading1')
    & $add (PT 'From a Windows command prompt in the repository root:')
    & $add (Pg (Rn "tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target $($m.Target)" $true '1F3864') '' '' $false 40)
    & $add (PT 'runs export, import, verification, the tooling self-test and this report. Individual steps: export, import, verify, selftest, report.')
    & $add (Table @(2800, 6560) @('Item', 'Value') @(
        , @('Tooling git commit', [string]$m.GitCommit)
        , @('Source server', [string]$m.SourceVersion)
        , @('Target client', [string]$m.TargetClient)
        , @('Run time (UTC)', [string]$m.RunTimeUtc)
        , @('01-schema.sql SHA-256', [string]$m.ExportSchemaSha256)
        , @($(if ($m.SanitizeCredentials) { '02-data-sanitized.sql SHA-256' } else { '02-data.sql SHA-256' }), [string]$m.ExportDataSha256)
        , @("$tn target", [string]$loc)
        , @('Target fingerprint (SHA-256)', $(if ($m.TargetFingerprint) { [string]$m.TargetFingerprint } else { 'n/a (server-hosted database)' }))
    ))

    # ---- 11 sign-off
    & $add (PT '11. Sign-off' 'Heading1')
    & $add (Table @(2400, 2800, 2200, 1960) @('Role', 'Name', 'Signature', 'Date') @(
        , @('Prepared by', '', '', '')
        , @('Technical reviewer', '', '', '')
        , @('Business approver', '', '', '')
    ))

    # ---- appendix
    & $add (PageBreak)
    & $add (PT 'Appendix A. Full row hashes' 'Heading1')
    & $add (PT 'SHA-256 over all rows of each table (canonical form, fixed order), computed independently on the source and on the target.')
    $split = { param($h) $h.Substring(0, 32) + "`n" + $h.Substring(32) }
    $hrows = foreach ($t in $tables) { , @($t.Name, (& $split $t.SourceHash), (& $split $t.TargetHash), (ResultCell ($t.SourceHash -eq $t.TargetHash))) }
    & $add (Table @(1000, 3700, 3700, 960) @('Table', 'Source SHA-256', 'Target SHA-256', 'Match') $hrows)

    return $b.ToString()
}

# ------------------------------------------------------------------ packaging

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

function Invoke-Report($Config, [string]$Target, [string]$Out) {
    $paths = Get-TargetPaths $Config $Target
    if (-not (Test-Path $paths.Results)) { throw (New-MigrationError "Missing $($paths.Results) - run 'verify' first." 2) }
    $results = Get-Content $paths.Results -Raw -Encoding UTF8 | ConvertFrom-Json
    $selfPath = Join-Path $paths.Dir 'selftest-results.json'
    $self = if (Test-Path $selfPath) { Get-Content $selfPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $outFile = if ($Out) { Resolve-RepoPath $Out } else { $paths.Report }

    $images = [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList) }
    $body = Build-ReportDocument $results $self $images
    $created = ([datetime]::ParseExact($results.Meta.RunTimeUtc, 'yyyy-MM-dd HH:mm:ss', $script:Inv)).ToString('yyyy-MM-ddTHH:mm:ssZ', $script:Inv)
    $hdrText = if ($results.Meta.Iteration) { "MasterAntiqueRepair - Iteration $($results.Meta.Iteration) - Database Migration Verification" } else { 'MasterAntiqueRepair - Database Migration Verification' }
    Save-Docx $outFile $body $images "Commit $($results.Meta.GitCommit) | $($results.Meta.RunTimeUtc) UTC" $created $hdrText
    Write-Host "Report: $outFile ($([Math]::Round((Get-Item $outFile).Length / 1KB)) KB, $($images.Items.Count) charts)"
    return $outFile
}
