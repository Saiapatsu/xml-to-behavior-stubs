--[[

WIP XML parsing tools
Included with xml-to-behavior-stubs

]]

local function pS(str, where)
	return string.match(str, "^[ \t\r\n]+()", where)
end

local xmls = {}

local function parse(self, str, where)
	coroutine.yield() -- wait for arguments
	
	while true do
		assert(where, "lost track of location")
		
		local there = string.match(str, "^[^<]*()", where) -- find next tag or eof
		if there ~= where then -- emit text if any
			coroutine.yield("text", string.sub(str, where, there - 1), where)
		end
		if there == #str + 1 then break end -- stop at eof
		
		where = there + 1
		local sigil = string.sub(str, where, where)
		
		-- according to w3schools, xml tag names:
		-- * must start with a letter or underscore
		-- * cannot start with xml (case-insensitive)
		-- * can contain letters, digits, hyphens, underscores, and periods
		-- * "letter" does include utf8
		-- fuck all of that
		if string.match(sigil, "[^!? \r\n\t/>]") then
			there = string.match(str, "^[^ \r\n\t/>]*()", where + 1)
			local tagname = string.sub(str, where, there - 1)
			
			coroutine.yield("tag", tagname, where - 1)
			
			-- attributes
			-- for attr, value in parser, true do ... end
			while true do
				there = string.match(str, "^[ \r\n\t]*()", there)
				
				local attrname, quotepos = string.match(str, "^([^ \r\n\t=/>]+)[ \r\n\t]*=[ \r\n\t]*()", there)
				if attrname == nil then
					-- no more attributes
					coroutine.yield(nil, tagname, there)
					break
				end
				
				local quote = string.sub(str, quotepos, quotepos)
				if quote == '"' then
					quote, there = string.match(str, "([^\"]*)\"()", quotepos + 1)
				elseif quote == "'" then
					quote, there = string.match(str, "([^\']*)\'()", quotepos + 1)
				else
					error("unquoted attribute value")
				end
				assert(quote, "incomplete attribute value")
				
				coroutine.yield(attrname, quote, there)
			end
			
			there = assert(string.match(str, ">()", there), "incomplete opening tag")
			
			if string.sub(str, there - 2, there - 2) == "/" then
				-- self-closing. location is where the end tag would be if there were one
				coroutine.yield(nil, tagname, there)
			end
			
		elseif sigil == "/" then
			-- closing tag. non-conformant
			there = assert(string.match(str, ">()", where + 1), "incomplete closing tag")
			coroutine.yield(nil, string.sub(str, where + 1, there - 2), where - 1)
			
		elseif sigil == "!" and string.sub(str, where + 1, where + 2) == "--" then
			-- comment
			there = assert(string.match(str, "%-%->()", where + 3), "incomplete comment tag")
			coroutine.yield("comment", string.sub(str, where + 3, there - 4), where - 1)
			
		elseif sigil == "?" then
			-- processing instruction
			there = assert(string.match(str, "%?>()", where + 1), "incomplete pi")
			coroutine.yield("pi", string.sub(str, where + 1, there - 3), where - 1)
			
		else
			-- unrecognized
			there = assert(string.match(str, ">()", there), "incomplete unknown tag")
			coroutine.yield("unknown", string.sub(str, where, there - 2), where - 1)
		end
		
		assert(where ~= there, "stuck")
		where = there
	end
end

function xmls.parser(str)
	local parser = setmetatable({str = str}, {__call = coroutine.wrap(parse)})
	parser(str, 1)
	return parser
end

-- ============================================================================
-- usage functions
-- ============================================================================

function xmls.waste(parser)
	xmls.wasteAttr(parser)
	return xmls.wasteContent(parser)
end

function xmls.wasteAttr(parser)
	for _ in parser do end
end

-- ignore contents of current tag
function xmls.wasteContent(parser)
	local level = 1
	repeat
		local type = parser()
		if
			type == "tag" then level = level + 1 xmls.wasteAttr(parser) elseif
			type ==  nil  then level = level - 1
		end
	until level == 0
end

-- of next tag, return tag name, location
-- or return closing tag
-- remember to consume or waste all tags
function xmls.tags(parser)
	while true do
		local type, tag, loc = parser()
		if type == "tag" then
			return tag, loc
		elseif type == nil then
			return nil, loc
		end
	end
end

-- of next tag, return tag name, text content, tag location, text location, etag location
-- or return closing tag
function xmls.kvtags(parser)
	while true do
		local type, tag, tagloc = parser()
		if type == "tag" then
			return tag, xmls.texttag(parser, tag, tagloc)
		elseif type == nil then
			return nil, tag, tagloc
		end
	end
end

-- of the current tag, which must contain only text, get the text content
-- discards attributes!
function xmls.texttag(parser, tag, tagloc)
	xmls.wasteAttr(parser) -- todo: also return attributes in some way?
	local type, value, valueloc = parser()
	if type == nil then return "", tagloc, valueloc, valueloc end
	assert(type == "text", "kvtag contains non-text")
	local type, etag, etagloc = parser()
	assert(type == nil, "kvtag contains non-text")
	assert(etag == tag, "mismatching closing tag")
	return value, tagloc, valueloc, etagloc
end

-- for each tag, run a corresponding function or waste it
-- footgun: each tag handler must consume all of its contents AND its
-- closing tag, which parser.tags() will do unless interrupted
function xmls.scan(parser, tbl)
	for tag in xmls.tags, parser do
		-- print(tag)
		local handler = tbl[tag]
		local t = type(handler)
		if
			t == "nil"      then xmls.waste(parser) elseif
			t == "function" then handler(parser, tag) elseif
			t == "table"    then xmls.wasteAttr(parser) xmls.scan(parser, handler)
		else
			error("invalid scanner", 2)
		end
	end
end

return xmls
