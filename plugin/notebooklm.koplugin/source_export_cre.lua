local has_util, util = pcall(require, "util")

local SourceExportCRE = {}

local WHOLE_DOCUMENT_XPOINTER = ".0"
local DEFAULT_HTML_FLAGS = 0x6830

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function collapse_blank_lines(value)
    value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    value = value:gsub("\194\160", " ")
    value = value:gsub("\194\173", "")
    value = value:gsub("[ \t]+\n", "\n")
    value = value:gsub("\n[ \t]+", "\n")
    value = value:gsub("[ \t][ \t]+", " ")
    value = value:gsub("\n\n\n+", "\n\n")
    return trim(value)
end

local function decode_entity(entity)
    local named = {
        amp = "&",
        lt = "<",
        gt = ">",
        quot = '"',
        apos = "'",
        nbsp = " ",
    }
    if named[entity] then
        return named[entity]
    end
    local decimal = entity:match("^#(%d+)$")
    if decimal then
        local code = tonumber(decimal)
        if code and code < 128 then
            return string.char(code)
        end
    end
    return "&" .. entity .. ";"
end

local function decode_entities(value)
    if has_util and util.htmlEntitiesToUtf8 then
        return util.htmlEntitiesToUtf8(value)
    end
    return tostring(value or ""):gsub("&([#%w]+);", decode_entity)
end

function SourceExportCRE.html_to_markdown(html)
    local text = tostring(html or "")
    text = text:gsub("<!%-%-.-%-%->", "")
    text = text:gsub("<%s*script[^>]*>.-<%s*/%s*script%s*>", "")
    text = text:gsub("<%s*style[^>]*>.-<%s*/%s*style%s*>", "")
    text = text:gsub("<%s*head[^>]*>.-<%s*/%s*head%s*>", "")
    text = text:gsub("<%s*[hH]1[^>]*>", "\n# ")
    text = text:gsub("<%s*/%s*[hH]1%s*>", "\n\n")
    text = text:gsub("<%s*[hH]2[^>]*>", "\n## ")
    text = text:gsub("<%s*/%s*[hH]2%s*>", "\n\n")
    text = text:gsub("<%s*[hH]3[^>]*>", "\n### ")
    text = text:gsub("<%s*/%s*[hH]3%s*>", "\n\n")
    text = text:gsub("<%s*li[^>]*>", "\n- ")
    text = text:gsub("<%s*/%s*li%s*>", "\n")
    text = text:gsub("<%s*br%s*/?%s*>", "\n")
    text = text:gsub("<%s*/%s*[pP]%s*>", "\n\n")
    text = text:gsub("<%s*/%s*[dD][iI][vV]%s*>", "\n\n")
    text = text:gsub("<%s*/%s*[sS][eE][cC][tT][iI][oO][nN]%s*>", "\n\n")
    text = text:gsub("<%s*/%s*[aA][rR][tT][iI][cC][lL][eE]%s*>", "\n\n")
    text = text:gsub("<[^>]+>", "")
    text = decode_entities(text)
    text = text:gsub("[ \t][ \t]+", " ")
    return collapse_blank_lines(text)
end

local function page_count(document)
    if type(document.getPageCount) == "function" then
        local ok, count = pcall(document.getPageCount, document)
        if ok and tonumber(count) then
            return tonumber(count)
        end
    end
    return nil
end

local function ensure_rendered(document, opts)
    opts = opts or {}
    if type(document.setViewDimen) == "function" then
        pcall(document.setViewDimen, document, {
            w = tonumber(opts.view_width or 600) or 600,
            h = tonumber(opts.view_height or 800) or 800,
        })
    end
    if type(document.setViewMode) == "function" then
        pcall(document.setViewMode, document, opts.view_mode or "page")
    end
    if type(document.render) == "function" then
        pcall(document.render, document)
    end
end

function SourceExportCRE.extract_whole_html(document, opts)
    opts = opts or {}
    if type(document) ~= "table" or type(document.getHTMLFromXPointer) ~= "function" then
        return nil, "Document does not expose whole-document HTML extraction."
    end
    local ok, html = pcall(
        document.getHTMLFromXPointer,
        document,
        WHOLE_DOCUMENT_XPOINTER,
        opts.html_flags or DEFAULT_HTML_FLAGS,
        true
    )
    if not ok or not html or html == "" then
        return nil, "Whole-document HTML extraction returned no content."
    end
    local markdown = SourceExportCRE.html_to_markdown(html)
    if markdown == "" then
        return nil, "Whole-document HTML extraction produced empty Markdown."
    end
    return {
        method = "cre-dom-html",
        text = markdown,
        char_count = #markdown,
    }
end

function SourceExportCRE.extract_page_text(document, opts)
    opts = opts or {}
    if type(document) ~= "table"
        or type(document.getPageXPointer) ~= "function"
        or type(document.getTextFromXPointers) ~= "function" then
        return nil, "Document does not expose page text extraction."
    end
    local count = page_count(document)
    if not count or count < 1 then
        ensure_rendered(document, opts)
        count = page_count(document)
    end
    if not count or count < 1 then
        return nil, "Document page count is unavailable."
    end

    local chunks = {}
    local max_pages = math.min(count, tonumber(opts.max_pages or count) or count)
    for page = 1, max_pages do
        local ok_start, pos0 = pcall(document.getPageXPointer, document, page)
        local ok_end, pos1 = pcall(document.getPageXPointer, document, page + 1)
        if ok_start and pos0 then
            local ok_text, text = pcall(document.getTextFromXPointers, document, pos0, ok_end and pos1 or nil, true)
            text = ok_text and trim(text) or ""
            if text ~= "" then
                chunks[#chunks + 1] = text
            end
        end
    end

    local markdown = collapse_blank_lines(table.concat(chunks, "\n\n"))
    if markdown == "" then
        return nil, "Page text extraction produced empty Markdown."
    end
    return {
        method = "cre-page-xpointers",
        text = markdown,
        char_count = #markdown,
        page_count = count,
    }
end

function SourceExportCRE.extract(document, opts)
    opts = opts or {}
    local page_result = SourceExportCRE.extract_page_text(document, opts)
    if page_result then
        return page_result
    end
    if opts.allow_whole_html == true then
        return SourceExportCRE.extract_whole_html(document, opts)
    end
    return nil, "Could not extract this book with KOReader page text extraction."
end

return SourceExportCRE
