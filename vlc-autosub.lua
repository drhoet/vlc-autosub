-- "subtitles.lua" -- VLC Extension --
-- http://www.videolan.org/developers/vlc/share/lua/README.txt
-- http://www.lua.org/manual/5.1/manual.html
-- http://wiki.videolan.org/Developers_Corner
-- http://addons.videolan.org/CONTENT/content-files/140695-imdb.lua
-- 
require 'simplexml'

dlg = nil
list_widget = nil
found_subtitles = nil
token = nil

function descriptor()
	return {
		title = "Download subtitles from OpenSubtitles.org";
		version = "1.0";
		author = "shobu";
		url = "http://";
		--icon = icon;
		shortdesc = "Download subtitles from OpenSubtitles.org";
		description = "Downloads subtitles from the OpenSubtitles.org website by creating a hash and searching for it."
			.. "<br/><br/>Subtitles service powered by <a href=\"www.opensubtitles.org\">www.OpenSubtitles.org</a>.";
	}
end

function activate()
	vlc.msg.info("[subtitles] Activating extension. Enable debug logging for more information.")
	local item = vlc.input.item()
	local filename = getFileName(item)
	if filename then
		vlc.msg.dbg("[subtitles] Movie file: " .. filename)
		token = os_login()
		if token then
			local hash, size = movieHashAndSize(filename)
			found_subtitles = os_search_subtitles(token, hash, size)
			if found_subtitles then
				create_list_subtitles_dialog()
			else
				create_error_dialog("Error happened while retrieving subtitles. See log for more information.")
			end
		else
			create_error_dialog("Could't connect to OpenSubtitles.org")
		end
	else
		create_error_dialog("Error: No movie is loaded")
	end
	--local f = io.open("C:\OS.ico", "r")
	--local icon = f:read("*all")
	--icon = icon:gsub(".", function(c)
	--		return "\\" .. c:byte()
	--	end)
	--vlc.msg.info("*" .. icon .. "*")
	--f:close()
end

function deactivate()
	vlc.msg.info("[subtitles] Deactivating extension.")
	if token then
		os_logout(token)
	end
end

function create_error_dialog(msg)
	vlc.msg.dbg("[subtitles] Error: " .. msg)
	dlg = vlc.dialog("[subtitles] Error")
	dlg:add_label(msg, 1, 1, 3, 1)
	dlg:add_button("Close", close_dialog, 2, 2)
	dlg:show()
end

function create_list_subtitles_dialog()
	dlg = vlc.dialog("[subtitles] Search results")
	dlg:add_label("Choose the subtitle you want to download:", 1, 1)
	list_widget = dlg:add_list(1, 2, 3, 1)
	
	table.sort(found_subtitles, function(a, b) return tonumber(a.SubDownloadsCnt) > tonumber(b.SubDownloadsCnt) end)
	for i, sub in ipairs(found_subtitles) do
		list_widget:add_value(nvl(sub.MovieReleaseName) .. "\n    " .. nvl(sub.SubSumCD) .. "CD -- Downloaded " .. nvl(sub.SubDownloadsCnt) .. "x -- " .. nvl(sub.SubFormat) .. " -- rating: " .. nvl(sub.SubRating), i)
	end
	dlg:add_button("Download", download_selected, 1, 3)
	dlg:add_button("Cancel", close_dialog, 3, 3)
	dlg:show()
end

function nvl(value, default)
	return value or default or '(null)'
end

function close_dialog()
	dlg:delete()
	
	token = nil
	list_widget = nil
	found_subtitles = nil
	dlg = nil
	
	vlc.deactivate()
end

function download_selected()
	local item = vlc.input.item()
	local path = getFilePath(getFileName(item))
	for index, name in pairs(list_widget:get_selection()) do
		local id = found_subtitles[index].IDSubtitleFile
		local stream = vlc.stream("zip://" .. found_subtitles[index].ZipDownloadLink .. "!/" .. found_subtitles[index].SubFileName)
		local ofh = assert(io.open(path .. found_subtitles[index].SubFileName, "wb"))
		local data = stream:readline()
		while data do
			ofh:write(data.."\n")
			data = stream:readline()
		end
		ofh:flush()
		ofh:close()
		stream = nil
		vlc.msg.info("Adding subtitle: " .. path .. found_subtitles[index].SubFileName)
		vlc.input.add_subtitle("file:///" .. path .. found_subtitles[index].SubFileName)
	end
	close_dialog()
end

function getFileName(item)
	if item then
		if string.sub(item:uri(), 0, 8) == "file:///" then
			return url_decode(string.sub(item:uri(), 9))
		end
	end
end

function getFilePath(item)
	if item then
		local pos = string.find(item, "/")
		local path = ""
		while pos do
			path = string.sub(item, 1, pos)
			pos = string.find(item, "/", pos + 1)
		end
		return path
	end
end

function url_decode(str)
	str = string.gsub (str, "+", " ")
	str = string.gsub (str, "%%(%x%x)",
		function(h) return string.char(tonumber(h,16)) end)
	str = string.gsub (str, "\r\n", "\n")
	return str
end

function url_encode(str)
	if (str) then
		str = string.gsub (str, "\n", "\r\n")
		str = string.gsub (str, "([^%w ])",
			function (c) return string.format ("%%%02X", string.byte(c)) end)
		str = string.gsub (str, " ", "+")
	end
	return str	
end

-- will produce a correct hash regardless of architecture (big vs little endian)
function movieHashAndSize(fileName)
	local fil = io.open(fileName, "rb")
	local lo,hi=0,0
	for i=1,8192 do
		local a,b,c,d = fil:read(4):byte(1,4)
		lo = lo + a + b*256 + c*65536 + d*16777216
		a,b,c,d = fil:read(4):byte(1,4)
		hi = hi + a + b*256 + c*65536 + d*16777216
		while lo>=4294967296 do
			lo = lo-4294967296
			hi = hi+1
		end
		while hi>=4294967296 do
			hi = hi-4294967296
		end
	end
	local size = fil:seek("end", -65536) + 65536
	for i=1,8192 do
		local a,b,c,d = fil:read(4):byte(1,4)
		lo = lo + a + b*256 + c*65536 + d*16777216
		a,b,c,d = fil:read(4):byte(1,4)
		hi = hi + a + b*256 + c*65536 + d*16777216
		while lo>=4294967296 do
			lo = lo-4294967296
			hi = hi+1
		end
		while hi>=4294967296 do
			hi = hi-4294967296
		end
	end
	lo = lo + size
		while lo>=4294967296 do
			lo = lo-4294967296
			hi = hi+1
		end
		while hi>=4294967296 do
			hi = hi-4294967296
		end
	fil:close()
	return string.format("%08x%08x", hi,lo), size
end

function os_login()
	vlc.msg.dbg("os_login")
	local xml = xmlrpc_create_request("LogIn", {"", "", "en", "OS Test User Agent"} )
	local response = xmlrpc_execute_request(xml)
	return response[1].token
end

function os_logout(token)
	vlc.msg.dbg("os_logout")
	local xml = xmlrpc_create_request("LogOut", {token} )
	local response = xmlrpc_execute_request(xml)
	return response[1].status
end

function os_search_subtitles(token, hash, size)
	vlc.msg.dbg("os_search_subtitles")
	local xml = xmlrpc_create_request("SearchSubtitles", {token, {{ sublanguageid = "eng", moviehash = hash, moviebytesize = size}}} )
	local response = xmlrpc_execute_request(xml)
	return response[1].data
end

function os_download_subtitles(token, ids)
	vlc.msg.dbg("os_download_subtitles")
	local xml = xmlrpc_create_request("DownloadSubtitles", {token, ids} )
	local response = xmlrpc_execute_request(xml)
	return response[1].data
end

function xmlrpc_create_request(method, args)
	local result = "<?xml version=\"1.0\"?><methodCall><methodName>" .. method
		.. "</methodName><params>"
	for i, v in pairs(args) do
		result = result .. "<param><value>" .. xmlrpc_create_value(v) .. "</value></param>"
	end
	return result .. "</params></methodCall>"
end

function xmlrpc_create_value(obj)
	if type(obj) == "string" then
		return "<string>" .. obj .. "</string>"
	elseif type(obj) == "number" then
		if math.floor(obj) == obj then
			return "<int>" .. obj .. "</int>"
		else
			return "<double>" .. obj .. "</double>"
		end
	elseif type(obj) == "table" then
		if isArray(obj) then
			return xmlrpc_array_to_str(obj)
		else
			return xmlrpc_struct_to_str(obj)
		end
	else
		vlc.msg.warn("Unknown type in xmlrpc_create_value: " .. type(obj))
	end
end

function xmlrpc_array_to_str(arr)
	local result = "<array><data>"
	for i, v in ipairs(arr) do
		result = result .. "<value>" .. xmlrpc_create_value(v) .. "</value>"
	end
	result = result .. "</data></array>"
	return result
end

function xmlrpc_struct_to_str(struct)
	local result = "<struct>"
	for k, v in pairs(struct) do
		result = result .. "<member><name>" .. k .. "</name>"
		result = result .. "<value>" .. xmlrpc_create_value(v) .. "</value></member>"
	end
	result = result .. "</struct>"
	return result
end

function xmlrpc_execute_request(xml)
	local req = "POST /xml-rpc HTTP/1.1"
			.. "\nHost: api.opensubtitles.org"
			.. "\nUser-Agent: OS Test User Agent"
			.. "\nContent-Length: " .. xml:len()
			.. "\n\n" -- end headers
			--.. url_encode(xml)
			.. xml

	vlc.msg.dbg("HTTP Request: " .. req)
	local response
	local status, response = http_req("api.opensubtitles.org", 80, req)

	if status == 200 then 
		return xmlrpc_parse_response(response)
	else
		vlc.msg.dbg("Error: response code " .. status)
		return false
	end
end

function xmlrpc_parse_response(response)
	--vlc.msg.dbg(response)
	local result_map = simplexml.parse_string(response)
	return xmlrpc_parse_parameters(result_map)
end

function xmlrpc_parse_parameters(tbl)
	local param_array = {}
	if tbl.name == "param" then
		table.insert(param_array, 1, xmlrpc_parse_value_element(tbl.children[1].children[1]))
	elseif tbl.children then
		for i, c in pairs(tbl.children) do
			local params = xmlrpc_parse_parameters(c)
			for i, p in pairs(params) do
				table.insert(param_array, #param_array + 1, p)
			end
		end
	end
	return param_array
end

function xmlrpc_parse_value_element(el)
	local result
	if el.name == "struct" then
		result = {}
		for i, member in pairs(el.children) do
			local name
			local value
			for j, c in pairs(member.children) do
				if c.name == "name" then
					name = c.children[1]
				elseif c.name == "value" then
					value = xmlrpc_parse_value_element(c.children[1])
				end
			end
			result[name] = value
		end
	elseif el.name == "array" then
		result = {}
		for i, value in pairs(el.children[1].children) do
			table.insert(result, #result + 1, xmlrpc_parse_value_element(value.children[1]))
		end
	elseif el.name == "string" then
		result = el.children[1]
	elseif el.name == "double" then
		result = tonumber(el.children[1])
	elseif el.name == "int" then
		result = tonumber(el.children[1])
	else
		vlc.msg.warn("Unknown tag in xmlrpc_parse_value_element: " .. el.name)
	end
	return result
end

function http_req(host, port, request)
   local fd = vlc.net.connect_tcp(host, port)
   if fd >= 0 then
      local pollfds = {}
      
      pollfds[fd] = vlc.net.POLLIN
      vlc.net.send(fd, request)
      vlc.net.poll(pollfds)
      
      local response = vlc.net.recv(fd, 1024)
	  local headerStr, body = string.match(response, "(.-\r?\n)\r?\n(.*)")
      local header = http_parse_header(headerStr)
      local contentLength = tonumber(header["Content-Length"])
      local TransferEncoding = header["Transfer-Encoding"]
      local status = tonumber(header["statuscode"])
	  if status ~= 200 then
		vlc.msg.dbg("HTTP Response: " .. response)
	  end
      local bodyLenght = string.len(body)
      local pct = 0
      
      if status ~= 200 then return status end
      
      while contentLength and bodyLenght < contentLength do
         vlc.net.poll(pollfds)
         response = vlc.net.recv(fd, 1024)

         if response then
            body = body..response
         else
            vlc.net.close(fd)
            return false
         end
         bodyLenght = string.len(body)
         pct = bodyLenght / contentLength * 100
         --setMessage(openSub.actionLabel..": "..progressBarContent(pct))
      end
      vlc.net.close(fd)
      
      return status, body
   end
   return ""
end

function http_parse_header(data)
   local header = {}
   
   for name, s, val in string.gfind(data, "([^%s:]+)(:?)%s([^\n]+)\r?\n") do
      if s == "" then header['statuscode'] =  tonumber(string.sub (val, 1 , 3))
      else header[name] = val end
   end
   return header
end

---Checks if a table is used as an array. That is: the keys start with one and are sequential numbers
-- @param t table
-- @return nil,error string if t is not a table
-- @return true/false if t is an array/isn't an array
-- NOTE: it returns true for an empty table
function isArray(t)
    if type(t)~="table" then return nil,"Argument is not a table! It is: "..type(t) end
    --check if all the table keys are numerical and count their number
    local count=0
    for k,v in pairs(t) do
        if type(k)~="number" then return false else count=count+1 end
    end
    --all keys are numerical. now let's see if they are sequential and start with 1
    for i=1,count do
        --Hint: the VALUE might be "nil", in that case "not t[i]" isn't enough, that's why we check the type
        if not t[i] and type(t[i])~="nil" then return false end
    end
    return true
end

local base64_b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function base64_decode(data)
    data = string.gsub(data, '[^'..base64_b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(base64_b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

--icon = "\71\73\70\56\57\97\16\0\16\0\179\0\0\0\0\0\17\17\17\34\34\34\51\51\51\68\68\68\85\85\85\119\119\119\136\136\136\153\153\153\170\170\170\204\204\204\221\221\221\238\238\238\255\255\255\0\0\0\0\0\0\33\249\4\9\0\0\14\0\44\0\0\0\0\16\0\16\0\0\4\74\16\200\73\171\108\13\96\157\247\230\160\215\101\86\105\158\21\130\37\146\192\96\12\101\32\82\98\0\10\1\4\11\181\8\18\30\96\161\179\48\2\193\24\1\179\24\200\104\0\196\1\48\5\16\122\148\196\74\162\120\53\10\168\176\248\50\10\149\205\232\207\88\18\1\0\59"
--icon = "\0\0\1\0\1\0\16\16\0\0\1\0\24\0\104\3\0\0\22\0\0\0\40\0\0\0\16\0\0\0\32\0\0\0\1\0\24\0\0\0\0\0\0\0\0\0\72\0\0\0\72\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\170\170\170\255\255\255\255\255\255\170\170\170\0\0\0\0\0\0\204\204\204\238\238\238\255\255\255\255\255\255\85\85\85\0\0\0\0\0\0\0\0\0\0\0\0\119\119\119\153\153\153\0\0\0\0\0\0\153\153\153\136\136\136\0\0\0\136\136\136\0\0\0\0\0\0\68\68\68\221\221\221\0\0\0\0\0\0\0\0\0\0\0\0\238\238\238\17\17\17\0\0\0\0\0\0\17\17\17\238\238\238\0\0\0\68\68\68\255\255\255\255\255\255\221\221\221\51\51\51\0\0\0\0\0\0\0\0\0\0\0\0\221\221\221\34\34\34\0\0\0\0\0\0\17\17\17\221\221\221\0\0\0\221\221\221\68\68\68\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\119\119\119\153\153\153\0\0\0\0\0\0\170\170\170\119\119\119\0\0\0\204\204\204\68\68\68\0\0\0\17\17\17\221\221\221\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\153\153\153\255\255\255\255\255\255\170\170\170\0\0\0\0\0\0\34\34\34\238\238\238\255\255\255\255\255\255\238\238\238\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\255\255\255\255\255\255\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"