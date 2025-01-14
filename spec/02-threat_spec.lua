local d = require("pl.stringx").dedent or require("pl.text").dedent

describe("threats", function()

	local sep = string.char(1)
	local threat = {
		depth = 3,				-- depth of tags

		-- counts
		maxChildren = 3,		-- max number of children (DOM2;  Element, Text, Comment,
		                        -- ProcessingInstruction, CDATASection). NOTE: adjacent text/CDATA
								-- sections are counted as 1 (so text-cdata-text-cdata is 1 child).
		maxAttributes = 3,		-- max number of attributes (including default ones), if not parsing
								-- namespaces, then the namespaces will be counted as attributes.
		maxNamespaces = 3,		-- max number of namespaces defined on a tag

		-- size limits
		document = 200,			-- size of entire document in bytes
		buffer = 100,			-- size of the unparsed buffer
		comment = 20,			-- size of comment in bytes
		localName = 20,			-- size of localname (or full name if not parsing namespaces) in bytes,
								-- applies to tags and attributes
		prefix = 20,			-- size of prefix in bytes (only if parsing namespaces), applies to
								-- tags and attributes
		namespaceUri = 20,		-- size of namespace uri in bytes (only if parsing namespaces)
		attribute = 20,			-- size of attribute value in bytes
		text = 20,				-- text inside tags (counted over all adjacent text/CDATA)
		PITarget = 20,			-- size of processing instruction target in bytes
		PIData = 20,			-- size of processing instruction data in bytes
		entityName = 20,		-- size of entity name in EntityDecl in bytes
		entity = 20,			-- size of entity value in EntityDecl in bytes
		entityProperty = 20,	-- size of systemId, publicId, or notationName in EntityDecl in bytes
	}

	local threat_no_ns = {} -- same as above, except without namespaces
	for k,v in pairs(threat) do threat_no_ns[k] = v end
	threat_no_ns.maxNamespaces = nil
	threat_no_ns.prefix = nil
	threat_no_ns.namespaceUri = nil

	local callbacks_def = { -- all callbacks and their parameters
		AttlistDecl = { "parser", "elementName", "attrName", "attrType", "default", "required" },
		CharacterData = { "parser", "data" },
		Comment = { "parser", "data" },
		Default = { "parser", "data" },
		--DefaultExpand = { "parser", "data" }, -- overrides "Default" if set
		ElementDecl = { "parser", "name", "type", "quantifier", "children" },
		EndCdataSection = { "parser" },
		EndDoctypeDecl = { "parser" },
		EndElement = { "parser", "elementName" },
		EndNamespaceDecl = { "parser", "namespaceName" },
		EntityDecl = { "parser", "entityName", "is_parameter", "value", "base", "systemId", "publicId", "notationName" },
		ExternalEntityRef = { "parser", "subparser", "base", "systemId", "publicId" },
		NotStandalone = { "parser" },
		NotationDecl = { "parser", "notationName", "base", "systemId", "publicId" },
		ProcessingInstruction = { "parser", "target", "data" },
		StartCdataSection = { "parser" },
		StartDoctypeDecl = { "parser", "name", "sysid", "pubid", "has_internal_subset" },
		StartElement = { "parser", "elementName", "attributes" },
		StartNamespaceDecl = { "parser", "namespaceName", "namespaceUri" },
		--UnparsedEntityDecl = { "parser", "entityName", "base", "systemId", "publicId", "notationName" },  -- superseeded by EntityDecl
		XmlDecl = { "parser", "version", "encoding", "standalone" },
	}

	local callbacks = {}
	local cbdata
	for cb, params in pairs(callbacks_def) do
		-- generate callbacks that just store the parameters
		callbacks[cb] = function(parser, ...)
			local info = {cb, ...}
			--print(cb, ...)
			cbdata[#cbdata+1] = info
		end
	end



	local p
	before_each(function()
		cbdata = {}
		callbacks.threat = threat
		p = require("lxp.threat").new(callbacks, sep, false)
	end)


	it("parses a simple xml", function()
		local r, err = p:parse(d[[
			<?xml version = "1.0" encoding = "UTF-8" standalone = "yes" ?>
			<root>hello</root>
		]])
		assert.equal(nil, err)
		assert.truthy(r)
		assert.same({
			{ "XmlDecl", "1.0", "UTF-8", true },
			{ "Default", "\n"},
			{ "StartElement", "root", {} },
			{ "CharacterData", "hello" },
			{ "EndElement", "root" },
			{ "Default", "\n\n"},
		}, cbdata)
	end)


	it("doesn't accept maxNamespaces, prefix, or namespaceUri without separator", function()
		callbacks.threat = {}
		for k,v in pairs(threat_no_ns) do callbacks.threat[k] = v end

		callbacks.threat.maxNamespaces = 1
		assert.has.error(function()
			require("lxp.threat").new(callbacks, nil, false)
		end, "expected separator to be set when checking maxNamespaces, prefix, and/or namespaceUri")
		callbacks.threat.maxNamespaces = nil

		callbacks.threat.prefix = 1
		assert.has.error(function()
			require("lxp.threat").new(callbacks, nil, false)
		end, "expected separator to be set when checking maxNamespaces, prefix, and/or namespaceUri")
		callbacks.threat.prefix = nil

		callbacks.threat.namespaceUri = 1
		assert.has.error(function()
			require("lxp.threat").new(callbacks, nil, false)
		end, "expected separator to be set when checking maxNamespaces, prefix, and/or namespaceUri")
		callbacks.threat.namespaceUri = nil
	end)



	describe("depth:", function()

		it("accepts on the edge (3)", function()
			local r, err = p:parse(d[[<root><l2><l3>hello</l3></l2></root>]])
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "StartElement", "l2", {} },
				{ "StartElement", "l3", {} },
				{ "CharacterData", "hello" },
				{ "EndElement", "l3" },
				{ "EndElement", "l2" },
				{ "EndElement", "root" },
				{ "Default", "\n"},
			}, cbdata)
		end)


		it("blocks over the edge (4)", function()
			local r, err = p:parse(d[[<root><l2><l3><l4>hello</l4></l3></l2></root>]])
			assert.equal("structure is too deep", err)
			assert.falsy(r)
		end)

	end)



	describe("children:", function()

		it("accepts on the edge (3)", function()
			local r, err = p:parse(d[[<root><c1/><c2/><c3/></root>]])
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "StartElement", "c1", {} },
				{ "EndElement", "c1" },
				{ "StartElement", "c2", {} },
				{ "EndElement", "c2" },
				{ "StartElement", "c3", {} },
				{ "EndElement", "c3" },
				{ "EndElement", "root" },
				{ "Default", "\n"},
			}, cbdata)
		end)


		it("treats adjacent text/CDATA as 1 child", function()
			local r, err = p:parse(d[=[<root><c1/><c2/>txt<![CDATA[in the middle]]>txt</root>]=])
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "StartElement", "c1", {} },
				{ "EndElement", "c1" },
				{ "StartElement", "c2", {} },
				{ "EndElement", "c2" },
				{ "CharacterData", "txt" },
				{ "StartCdataSection" },
				{ "CharacterData", "in the middle" },
				{ "EndCdataSection" },
				{ "CharacterData", "txt" },
				{ "EndElement", "root" },
				{ "Default", "\n"},
			}, cbdata)
		end)



		describe("blocks over the edge, counts:", function()

			it("element nodes", function()
				local r, err = p:parse(d[[<root><c1/><c2/><c3/><c4/></root>]])
				assert.equal("too many children", err)
				assert.falsy(r)
			end)


			it("Text nodes", function()
				local r, err = p:parse(d[[<root><c1/><c2/><c3/>c4 as text</root>]])
				assert.equal("too many children", err)
				assert.falsy(r)
			end)


			it("Comment nodes", function()
				local r, err = p:parse(d[[<root><c1/><c2/><c3/><!--c4 comment--></root>]])
				assert.equal("too many children", err)
				assert.falsy(r)
			end)


			it("ProcessingInstruction nodes", function()
				local r, err = p:parse(d[[<root><c1/><c2/><c3/><?target instructions?></root>]])
				assert.equal("too many children", err)
				assert.falsy(r)
			end)


			it("CDATASection nodes", function()
				local r, err = p:parse(d[=[<root><c1/><c2/><c3/><![CDATA[c4 as cdata]]></root>]=])
				assert.equal("too many children", err)
				assert.falsy(r)
			end)

		end)

	end)



	describe("maxAttributes", function()

		describe("accepts on the edge", function()

			it("plain attributes", function()
				local r, err = p:parse(d[[<root attra="a" attrb="b" attrc="c">txt</root>]])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {
						"attra", "attrb", "attrc",
						attra = "a",
						attrb = "b",
						attrc = "c",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
					{ "Default", "\n"},
				}, cbdata)
			end)


			it("attr+namespaces, separator", function()
				local r, err = p:parse(d[[
					<root attra="a" attrb="b" attrc="c" xmlns="http://ns" xmlns:hello="http://hello">txt</root>
				]])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartNamespaceDecl", nil, "http://ns" },
					{ "StartNamespaceDecl", "hello", "http://hello" },
					{ "StartElement", "http://ns"..sep.."root", {
						"attra", "attrb", "attrc",
						attra = "a",
						attrb = "b",
						attrc = "c",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "http://ns"..sep.."root" },
					{ "EndNamespaceDecl", "hello" },
					{ "EndNamespaceDecl" },
					{ "Default", "\n\n"},
				}, cbdata)
			end)


			it("attr+namespaces, no separator", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local r, err = p:parse(d[[
					<root attra="a" xmlns="http://ns" xmlns:hello="http://hello">txt</root>
				]])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {
						"attra", "xmlns", "xmlns:hello",
						attra = "a",
						xmlns = "http://ns",
						["xmlns:hello"] = "http://hello",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
					{ "Default", "\n\n"},
				}, cbdata)
			end)

		end)

		describe("blocks over the edge", function()

			it("plain attributes", function()
				local r, err = p:parse(d[[<root attra="a" attrb="b" attrc="c" attrd="d">txt</root>]])
				assert.equal("too many attributes", err)
				assert.falsy(r)
			end)


			it("attr+namespaces, separator", function()
				local r, err = p:parse(d[[
					<root attra="a" attrb="b" attrc="c" attrd="d" xmlns="http://ns" xmlns:hello="http://hello">txt</root>
				]])
				assert.equal("too many attributes", err)
				assert.falsy(r)
			end)


			it("attr+namespaces, no separator", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local r, err = p:parse(d[[
					<root attra="a" attrb="b" xmlns="http://ns" xmlns:hello="http://hello">txt</root>
				]])
				assert.equal("too many attributes", err)
				assert.falsy(r)
			end)

		end)

	end)



	describe("maxNamespaces", function()

		it("accepts on the edge", function()

			local r, err = p:parse(d[[
				<root xmlns="http://ns" xmlns:hello="http://hello" xmlns:world="http://world">txt</root>
			]])
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartNamespaceDecl", nil, "http://ns" },
				{ "StartNamespaceDecl", "hello", "http://hello" },
				{ "StartNamespaceDecl", "world", "http://world" },
				{ "StartElement", "http://ns"..sep.."root", {} },
				{ "CharacterData", "txt" },
				{ "EndElement", "http://ns"..sep.."root" },
				{ "EndNamespaceDecl", "world" },
				{ "EndNamespaceDecl", "hello" },
				{ "EndNamespaceDecl" },
				{ "Default", "\n\n"},
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local r, err = p:parse(d[[
				<root
					xmlns="http://ns"
					xmlns:hello="http://hello"
					xmlns:world="http://world"
					xmlns:panic="http://42"
				>txt</root>
			]])
			assert.equal("too many namespaces", err)
			assert.falsy(r)
		end)

	end)



	describe("document size", function()

		local old_buffer

		setup(function()
			old_buffer = threat.buffer
			threat.buffer = nil  -- disable unparsed buffer checks with these tests
		end)

		teardown(function()
			threat.buffer = old_buffer -- reenable old setting
		end)



		it("accepts on the edge as one", function()
			local doc = "<root>txt</root>"
			local txt = (" "):rep(200-#doc)
			doc = txt..doc
			assert.equal(200, #doc)
			local r, err = p:parse(doc)
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "Default", txt},
				{ "StartElement", "root", {} },
				{ "CharacterData", "txt" },
				{ "EndElement", "root" },
			}, cbdata)
		end)

		it("accepts on the edge chunked", function()
			local doc = "<root>txt</root>"
			local txt = (" "):rep(200-#doc)
			doc = txt..doc
			assert.equal(200, #doc)

			local r, err = p:parse(doc:sub(1,100))
			assert.equal(nil, err)
			assert.truthy(r)

			local r, err = p:parse(doc:sub(101,190))
			assert.equal(nil, err)
			assert.truthy(r)

			local r, err = p:parse(doc:sub(191,-1))
			assert.equal(nil, err)
			assert.truthy(r)

			assert.same({
				{ "Default", txt:sub(1,100)},
				{ "Default", txt:sub(101,-1)},
				{ "StartElement", "root", {} },
				{ "CharacterData", "txt" },
				{ "EndElement", "root" },
			}, cbdata)
		end)


		it("blocks over the edge, as one", function()
			local doc = "<root>txt</root>"
			local txt = (" "):rep(200-#doc + 1)  -- +1; over the edge
			doc = txt..doc
			assert.equal(201, #doc)
			local r, err = p:parse(doc)
			assert.equal("document too large", err)
			assert.falsy(r)
		end)


		it("blocks over the edge, chunked", function()
			local doc = "<root>txt</root>"
			local txt = (" "):rep(200-#doc + 1)  -- +1; over the edge
			doc = txt..doc
			assert.equal(201, #doc)

			local r, err = p:parse(doc:sub(1,100))
			assert.equal(nil, err)
			assert.truthy(r)

			local r, err = p:parse(doc:sub(101,190))
			assert.equal(nil, err)
			assert.truthy(r)

			local r, err = p:parse(doc:sub(191,-1))
			assert.equal("document too large", err)
			assert.falsy(r)
		end)

	end)



	describe("comment size", function()

		it("accepts on the edge", function()
			local doc = "<root><!--01234567890123456789--></root>"
			local r, err = p:parse(doc)
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "Comment", "01234567890123456789" },
				{ "EndElement", "root" },
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local doc = "<root><!--01234567890123456789x--></root>"
			local r, err = p:parse(doc)
			assert.equal("comment too long", err)
			assert.falsy(r)
		end)

	end)



	describe("localName size", function()

		describe("element, plain", function()

			it("accepts on the edge", function()
				local doc = "<roota12345abcde12345>txt</roota12345abcde12345>"
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "roota12345abcde12345", {} },
					{ "CharacterData", "txt" },
					{ "EndElement", "roota12345abcde12345" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = "<roota12345abcde12345x>txt</roota12345abcde12345x>"
				local r, err = p:parse(doc)
				assert.equal("element localName too long", err)
				assert.falsy(r)
			end)

		end)



		describe("element, namespaced with separator", function()

			it("accepts on the edge", function()
				local doc = [[<cool:roota12345abcde12345 xmlns:cool="http://cool">txt</cool:roota12345abcde12345>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartNamespaceDecl", "cool", "http://cool" },
					{ "StartElement", "http://cool"..sep.."roota12345abcde12345", {} },
					{ "CharacterData", "txt" },
					{ "EndElement", "http://cool"..sep.."roota12345abcde12345" },
					{ "EndNamespaceDecl", "cool" }
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = [[<cool:roota12345abcde12345x xmlns:cool="http://cool">txt</cool:roota12345abcde12345x>]]
				local r, err = p:parse(doc)
				assert.equal("element localName too long", err)
				assert.falsy(r)
			end)

		end)



		describe("element, namespaced without separator", function()

			it("accepts on the edge", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local doc = "<space:root12345abcde></space:root12345abcde>"
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "space:root12345abcde", {} },
					{ "EndElement", "space:root12345abcde" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local doc = "<spacex:root12345abcde></spacex:root12345abcde>"
				local r, err = p:parse(doc)
				assert.equal("element name too long", err)
				assert.falsy(r)
			end)

		end)



		describe("attribute, plain", function()

			it("accepts on the edge", function()
				local doc = [[<root attra12345abcde12345="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {
						"attra12345abcde12345",
						attra12345abcde12345 = "value",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = [[<root attra12345abcde12345x="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal("attribute localName too long", err)
				assert.falsy(r)
			end)

		end)



		describe("attribute, namespaced with separator", function()

			it("accepts on the edge", function()
				local doc = [[<root xmlns:yummy="http://nice" yummy:attra12345abcde12345="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartNamespaceDecl", "yummy", "http://nice" },
					{ "StartElement", "root", {
						"http://nice"..sep.."attra12345abcde12345",
						["http://nice"..sep.."attra12345abcde12345"] = "value",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
					{ "EndNamespaceDecl", "yummy" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = [[<root xmlns:yummy="http://nice" yummy:attra12345abcde12345x="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal("attribute localName too long", err)
				assert.falsy(r)
			end)

		end)



		describe("attribute, namespaced without separator", function()

			it("accepts on the edge", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local doc = [[<root yummy:attr12345abcde="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {
						"yummy:attr12345abcde",
						["yummy:attr12345abcde"] = "value",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				callbacks.threat = threat_no_ns
				p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
				local doc = [[<root yummy:attr12345abcdex="value">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal("attribute name too long", err)
				assert.falsy(r)
			end)

		end)



		describe("ElementDecl", function()

			local old_doc1, old_buffer1, old_doc2, old_buffer2
			setup(function()
				old_doc1 = threat.document
				old_buffer1 = threat.buffer
				old_doc2 = threat_no_ns.document
				old_buffer2 = threat_no_ns.buffer
				threat.document = nil  -- disable document checks with these tests
				threat.buffer = nil
				threat_no_ns.document = nil  -- disable document checks with these tests
				threat_no_ns.buffer = nil
			end)

			teardown(function()
				threat.document = old_doc1 -- reenable old setting
				threat.buffer = old_buffer1
				threat_no_ns.document = old_doc2 -- reenable old setting
				threat_no_ns.buffer = old_buffer2
			end)

			local xmldoc = function(elemPref, elemName, childPref, childName)
				local elem = (elemPref and (elemPref .. ":") or "")..elemName
				local attr = (childPref and (childPref .. ":") or "")..childName
				return string.format(d[[
					<?xml version="1.0" standalone="yes"?>
					<!DOCTYPE lab_group [
						<!ELEMENT %s (id|%s)>
					]>
				]], elem, attr)
			end


			describe("plain", function()

				it("accepts on the edge", function()
					local doc = xmldoc(nil, "student345abcde12345", nil, "surname345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "ElementDecl", "student345abcde12345", "CHOICE", nil, {
							{ name = "id", type = "NAME" },
							{ name = "surname345abcde12345", type = "NAME" },
						} },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks over the edge", function()
					local doc = xmldoc(nil, "student345abcde12345x", nil, "surname345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("elementDecl localName too long", err)
					assert.falsy(r)
				end)


				it("blocks child over the edge", function()
					local doc = xmldoc(nil, "student345abcde12345", nil, "surname345abcde12345x")
					local r, err = p:parse(doc)
					assert.equal("elementDecl localName too long", err)
					assert.falsy(r)
				end)

			end)



			describe("namespaced with separator", function()

				it("accepts localName+prefix on the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "student345abcde12345", "prefix2345abcde12345", "surname345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "ElementDecl", "prefix2345abcde12345:student345abcde12345", "CHOICE", nil, {
							{ name = "id", type = "NAME" },
							{ name = "prefix2345abcde12345:surname345abcde12345", type = "NAME" },
						} },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName over the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "student345abcde12345x", "prefix2345abcde12345", "surname345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("elementDecl localName too long", err)
					assert.falsy(r)
				end)


				it("blocks localName child over the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "student345abcde12345x", "prefix2345abcde12345", "surname345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("elementDecl localName too long", err)
					assert.falsy(r)
				end)

			end)



			describe("namespaced without separator", function()

				it("accepts localName+prefix on the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc("prefix2345", "student34", "prefix2345", "surname34")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "ElementDecl", "prefix2345:student34", "CHOICE", nil, {
							{ name = "id", type = "NAME" },
							{ name = "prefix2345:surname34", type = "NAME" },
						} },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName+prefix over the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc("prefix2345", "student345", "prefix2345", "surname34")
					local r, err = p:parse(doc)
					assert.equal("elementDecl name too long", err)
					assert.falsy(r)
				end)


				it("blocks localName+prefix child over the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc("prefix2345", "student34", "prefix2345", "surname345")
					local r, err = p:parse(doc)
					assert.equal("elementDecl name too long", err)
					assert.falsy(r)
				end)

			end)

		end)



		describe("AttlistDecl", function()

			local old_doc1, old_buffer1, old_doc2, old_buffer2
			setup(function()
				old_doc1 = threat.document
				old_buffer1 = threat.buffer
				old_doc2 = threat_no_ns.document
				old_buffer2 = threat_no_ns.buffer
				threat.document = nil  -- disable document checks with these tests
				threat.buffer = nil
				threat_no_ns.document = nil  -- disable document checks with these tests
				threat_no_ns.buffer = nil
			end)

			teardown(function()
				threat.document = old_doc1 -- reenable old setting
				threat.buffer = old_buffer1
				threat_no_ns.document = old_doc2 -- reenable old setting
				threat_no_ns.buffer = old_buffer2
			end)

			local xmldoc = function(ePref, eName, aPref, aName)
				local elem = (ePref and (ePref .. ":") or "")..eName
				local attr = (aPref and (aPref .. ":") or "")..aName
				return string.format(d[[
					<?xml version="1.0" standalone="yes"?>
					<!DOCTYPE lab_group [
						<!ATTLIST %s %s CDATA #FIXED "www.example.com">
					]>
				]], elem, attr)
			end


			describe("element, plain", function()

				it("accepts on the edge", function()
					local doc = xmldoc(nil, "roota12345abcde12345", nil, "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "roota12345abcde12345", "attra12345abcde12345", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks over the edge", function()
					local doc = xmldoc(nil, "roota12345abcde12345x", nil, "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("element localName too long", err)
					assert.falsy(r)
				end)

			end)



			describe("element, namespaced with separator", function()

				it("accepts localName+prefix on the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "roota12345abcde12345", "prefix2345abcde12345", "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "prefix2345abcde12345:roota12345abcde12345", "prefix2345abcde12345:attra12345abcde12345", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName over the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "roota12345abcde12345x", "prefix2345abcde12345", "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("element localName too long", err)
					assert.falsy(r)
				end)


				it("blocks prefix over the edge", function()
					local doc = xmldoc("prefix2345abcde12345x", "roota12345abcde12345", "prefix2345abcde12345", "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("element prefix too long", err)
					assert.falsy(r)
				end)

			end)



			describe("element, namespaced without separator", function()

				it("accepts localName+prefix on the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc(nil, "prefix2345:roota1234", nil, "prefix2345:attra1234")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "prefix2345:roota1234", "prefix2345:attra1234", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName+prefix over the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc(nil, "prefix2345:roota1234x", nil, "prefix2345:attra1234")
					local r, err = p:parse(doc)
					assert.equal("elementName too long", err)
					assert.falsy(r)
				end)

			end)



			describe("attribute, plain", function()

				it("accepts on the edge", function()
					local doc = xmldoc(nil, "roota12345abcde12345", nil, "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "roota12345abcde12345", "attra12345abcde12345", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks over the edge", function()
					local doc = xmldoc(nil, "roota12345abcde12345", nil, "attra12345abcde12345x")
					local r, err = p:parse(doc)
					assert.equal("attribute localName too long", err)
					assert.falsy(r)
				end)

			end)



			describe("attribute, namespaced with separator", function()

				it("accepts localName+prefix on the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "roota12345abcde12345", "prefix2345abcde12345", "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "prefix2345abcde12345:roota12345abcde12345", "prefix2345abcde12345:attra12345abcde12345", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName over the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "roota12345abcde12345", "prefix2345abcde12345", "attra12345abcde12345x")
					local r, err = p:parse(doc)
					assert.equal("attribute localName too long", err)
					assert.falsy(r)
				end)


				it("blocks prefix over the edge", function()
					local doc = xmldoc("prefix2345abcde12345", "roota12345abcde12345", "prefix2345abcde12345x", "attra12345abcde12345")
					local r, err = p:parse(doc)
					assert.equal("attribute prefix too long", err)
					assert.falsy(r)
				end)

			end)



			describe("attribute, namespaced without separator", function()

				it("accepts localName+prefix on the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc(nil, "prefix2345:roota1234", nil, "prefix2345:attra1234")
					local r, err = p:parse(doc)
					assert.equal(nil, err)
					assert.truthy(r)
					assert.same({
						{ "XmlDecl", "1.0", nil, true },
						{ "Default", "\n" },
						{ "StartDoctypeDecl", "lab_group", nil, nil, true },
						{ "Default", "\n\t" },
						{ "AttlistDecl", "prefix2345:roota1234", "prefix2345:attra1234", "CDATA", "www.example.com", true },
						{ "Default", "\n" },
						{ "EndDoctypeDecl" },
						{ "Default", "\n\n" },
					}, cbdata)
				end)


				it("blocks localName+prefix over the edge", function()
					callbacks.threat = threat_no_ns
					p = require("lxp.threat").new(callbacks, nil, false) -- new parser without separator
					local doc = xmldoc(nil, "prefix2345:roota1234", nil, "prefix2345:attra1234x")
					local r, err = p:parse(doc)
					assert.equal("attributeName too long", err)
					assert.falsy(r)
				end)

			end)

		end)

	end)



	describe("prefix size", function()

		describe("tag", function()

			it("accepts on the edge", function()
				local doc = [[<coola12345abcde12345:root xmlns:coola12345abcde12345="http://cool">txt</coola12345abcde12345:root>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartNamespaceDecl", "coola12345abcde12345", "http://cool" },
					{ "StartElement", "http://cool"..sep.."root", {} },
					{ "CharacterData", "txt" },
					{ "EndElement", "http://cool"..sep.."root" },
					{ "EndNamespaceDecl", "coola12345abcde12345" }
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = [[<coola12345abcde12345x:root xmlns:coola12345abcde12345x="http://cool">txt</coola12345abcde12345x:root>]]
				local r, err = p:parse(doc)
				assert.equal("prefix too long", err)
				assert.falsy(r)
			end)

		end)



		describe("attribute", function()

			it("accepts on the edge", function()
				local doc = [[<root xmlns:coola12345abcde12345="http://cool" coola12345abcde12345:attra="a">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartNamespaceDecl", "coola12345abcde12345", "http://cool" },
					{ "StartElement", "root", {
						"http://cool"..sep.."attra",
						["http://cool"..sep.."attra"] = "a",
					} },
					{ "CharacterData", "txt" },
					{ "EndElement", "root" },
					{ "EndNamespaceDecl", "coola12345abcde12345" }
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = [[<root xmlns:coola12345abcde12345x="http://cool" coola12345abcde12345x:attra="a">txt</root>]]
				local r, err = p:parse(doc)
				assert.equal("prefix too long", err)
				assert.falsy(r)
			end)

		end)

	end)



	describe("namespaceUri size", function()

		it("accepts on the edge", function()
			local doc = [[<root xmlns:cool="http://cool2345abcde">txt</root>]]
			local r, err = p:parse(doc)
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartNamespaceDecl", "cool", "http://cool2345abcde" },
				{ "StartElement", "root", {} },
				{ "CharacterData", "txt" },
				{ "EndElement", "root" },
				{ "EndNamespaceDecl", "cool" }
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local doc = [[<root xmlns:cool="http://cool2345abcdex">txt</root>]]
			local r, err = p:parse(doc)
			assert.equal("namespaceUri too long", err)
			assert.falsy(r)
		end)

	end)



	describe("attribute value size", function()

		it("accepts on the edge", function()
			local doc = [[<root attr="abcde12345abcde12345">txt</root>]]
			local r, err = p:parse(doc)
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {
					"attr",
					attr = "abcde12345abcde12345"
				} },
				{ "CharacterData", "txt" },
				{ "EndElement", "root" },
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local doc = [[<root attr="abcde12345abcde12345x">txt</root>]]
			local r, err = p:parse(doc)
			assert.equal("attribute value too long", err)
			assert.falsy(r)
		end)

	end)



	describe("text size", function()

		describe("text-node", function()

			it("accepts on the edge", function()
				local r, err = p:parse(d[[<root>abcde12345abcde12345</root>]])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {} },
					{ "CharacterData", "abcde12345abcde12345" },
					{ "EndElement", "root" },
					{ "Default", "\n" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local r, err = p:parse(d[[<root>abcde12345abcde12345x</root>]])
				assert.equal("text/CDATA node(s) too long", err)
				assert.falsy(r)
			end)

		end)



		describe("CDATA-node", function()

			it("accepts on the edge", function()
				local r, err = p:parse(d[=[<root><![CDATA[abcde12345abcde12345]]></root>]=])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {} },
					{ "StartCdataSection" },
					{ "CharacterData", "abcde12345abcde12345" },
					{ "EndCdataSection" },
					{ "EndElement", "root" },
					{ "Default", "\n" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local r, err = p:parse(d[=[<root><![CDATA[abcde12345abcde12345x]]></root>]=])
				assert.equal("text/CDATA node(s) too long", err)
				assert.falsy(r)
			end)

		end)


		describe("mixed text/CDATA", function()

			it("accepts on the edge", function()
				local r, err = p:parse(d[=[<root>txt<![CDATA[in the middle]]>txt!</root>]=])
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "StartElement", "root", {} },
					{ "CharacterData", "txt" },
					{ "StartCdataSection" },
					{ "CharacterData", "in the middle" },
					{ "EndCdataSection" },
					{ "CharacterData", "txt!" },
					{ "EndElement", "root" },
					{ "Default", "\n" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local r, err = p:parse(d[=[<root>txt<![CDATA[in the middle]]>txt!!</root>]=])
				assert.equal("text/CDATA node(s) too long", err)
				assert.falsy(r)
			end)


			describe("doesn't block if interleaved with other types: ", function()
				for t, sub in pairs {
							element = "<tag/>",
							comment = "<!--comment-->",
							process_instruction = "<?target instructions?>" } do

					it(t, function()
						local doc = [=[<root>abcde12345abcde12345%s<![CDATA[abcde12345abcde12345]]></root>]=]
						doc = doc:format(sub)
						local r, err = p:parse(doc)
						assert.equal(nil, err)
						assert.truthy(r)
					end)

				end

			end)

		end)

	end)



	describe("PITarget size", function()

		it("accepts on the edge", function()
			local r, err = p:parse("<root><?target2345abcde12345 instructions?></root>")
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "ProcessingInstruction", "target2345abcde12345", "instructions" },
				{ "EndElement", "root" },
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local r, err = p:parse("<root><?target2345abcde12345x instructions?></root>")
			assert.equal("processing instruction target too long", err)
			assert.falsy(r)
		end)

	end)



	describe("PIData size", function()

		it("accepts on the edge", function()
			local r, err = p:parse("<root><?target instructions345abcde?></root>")
			assert.equal(nil, err)
			assert.truthy(r)
			assert.same({
				{ "StartElement", "root", {} },
				{ "ProcessingInstruction", "target", "instructions345abcde" },
				{ "EndElement", "root" },
			}, cbdata)
		end)


		it("blocks over the edge", function()
			local r, err = p:parse("<root><?target instructions345abcdex?></root>")
			assert.equal("processing instruction data too long", err)
			assert.falsy(r)
		end)

	end)



	describe("entity", function()

		local old_doc1, old_buffer1, old_doc2, old_buffer2
		setup(function()
			old_doc1 = threat.document
			old_buffer1 = threat.buffer
			old_doc2 = threat_no_ns.document
			old_buffer2 = threat_no_ns.buffer
			threat.document = nil  -- disable document checks with these tests
			threat.buffer = nil
			threat_no_ns.document = nil  -- disable document checks with these tests
			threat_no_ns.buffer = nil
		end)

		teardown(function()
			threat.document = old_doc1 -- reenable old setting
			threat.buffer = old_buffer1
			threat_no_ns.document = old_doc2 -- reenable old setting
			threat_no_ns.buffer = old_buffer2
		end)

		local xmldoc = function(entity)
			return string.format(d[[
				<?xml version="1.0" standalone="yes"?>
				<!DOCTYPE greeting [
					%s
				]>
			]], entity)
		end


		describe("entityName size", function()

			it("accepts on the edge", function()
				local doc = xmldoc([[<!ENTITY xuxu5abcde12345abcde "is this a xuxu?12345">]])
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "XmlDecl", "1.0", nil, true },
					{ "Default", "\n" },
					{ "StartDoctypeDecl", "greeting", nil, nil, true },
					{ "Default", "\n\t" },
					{ "EntityDecl", "xuxu5abcde12345abcde", false, "is this a xuxu?12345" },
					{ "Default", "\n" },
					{ "EndDoctypeDecl" },
					{ "Default", "\n\n" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = xmldoc([[<!ENTITY xuxu5abcde12345abcdeX "is this a xuxu?12345">]])
				local r, err = p:parse(doc)
				assert.equal("entityName too long", err)
				assert.falsy(r)
			end)

		end)



		describe("entity size", function()

			it("accepts on the edge", function()
				local doc = xmldoc([[<!ENTITY xuxu5abcde12345abcde "is this a xuxu?12345">]])
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "XmlDecl", "1.0", nil, true },
					{ "Default", "\n" },
					{ "StartDoctypeDecl", "greeting", nil, nil, true },
					{ "Default", "\n\t" },
					{ "EntityDecl", "xuxu5abcde12345abcde", false, "is this a xuxu?12345" },
					{ "Default", "\n" },
					{ "EndDoctypeDecl" },
					{ "Default", "\n\n" },
				}, cbdata)
			end)


			it("blocks over the edge", function()
				local doc = xmldoc([[<!ENTITY xuxu5abcde12345abcde "is this a xuxu?12345x">]])
				local r, err = p:parse(doc)
				assert.equal("entity value too long", err)
				assert.falsy(r)
			end)

		end)



		describe("entityProperty size", function()

			it("accepts on the edge", function()
				p:setbase("/base")
				local doc = xmldoc(d[[
					<!ENTITY test1 SYSTEM "uri_e12345abcde12345" NDATA txt45abcde1234512345>
				    <!ENTITY test2 PUBLIC "public_id5abcde12345" "uri_e12345abcde12345" NDATA txt45abcde1234512345>]])
				local r, err = p:parse(doc)
				assert.equal(nil, err)
				assert.truthy(r)
				assert.same({
					{ "XmlDecl", "1.0", nil, true },
					{ "Default", "\n" },
					{ "StartDoctypeDecl", "greeting", nil, nil, true },
					{ "Default", "\n\t" },
					{ "EntityDecl", "test1", false, nil, "/base", "uri_e12345abcde12345", nil, "txt45abcde1234512345" },
					{ "Default", "\n   " },
					{ "EntityDecl", "test2", false, nil, "/base", "uri_e12345abcde12345", "public_id5abcde12345", "txt45abcde1234512345" },
					{ "Default", "\n\n" },
					{ "EndDoctypeDecl" },
					{ "Default", "\n\n" },
				}, cbdata)
			end)


			it("blocks systemId over the edge", function()
				p:setbase("/base")
				local doc = xmldoc(d[[
					<!ENTITY test1 SYSTEM "uri_e12345abcde12345x" NDATA txt45abcde1234512345>
				    <!ENTITY test2 PUBLIC "public_id5abcde12345" "uri_e12345abcde12345" NDATA txt45abcde1234512345>]])
				local r, err = p:parse(doc)
				assert.equal("systemId too long", err)
				assert.falsy(r)
			end)


			it("blocks publicId over the edge", function()
				p:setbase("/base")
				local doc = xmldoc(d[[
					<!ENTITY test1 SYSTEM "uri_e12345abcde12345" NDATA txt45abcde1234512345>
				    <!ENTITY test2 PUBLIC "public_id5abcde12345x" "uri_e12345abcde12345" NDATA txt45abcde1234512345>]])
				local r, err = p:parse(doc)
				assert.equal("publicId too long", err)
				assert.falsy(r)
			end)


			it("blocks notationName over the edge", function()
				p:setbase("/base")
				local doc = xmldoc(d[[
					<!ENTITY test1 SYSTEM "uri_e12345abcde12345" NDATA txt45abcde1234512345x>
				    <!ENTITY test2 PUBLIC "public_id5abcde12345" "uri_e12345abcde12345" NDATA txt45abcde1234512345>]])
				local r, err = p:parse(doc)
				assert.equal("notationName too long", err)
				assert.falsy(r)
			end)

		end)

	end)



	describe("buffer size", function()

		local old_doc

		setup(function()
			old_doc = threat.document
			threat.document = nil  -- disable document checks with these tests
		end)

		teardown(function()
			threat.document = old_doc -- reenable old setting
		end)



		it("blocks over the edge", function()
			local attrs = {}
			for i = 1,50 do
				attrs[i] = "attr"..i.."='abcde12345abcde12345'"
			end
			local doc = "<tag "..table.concat(attrs, " ")..">text</tag>"

			local i = 0
			local r, err
			repeat
				-- parse in chunks of 10 bytes
				i = i + 1
				local s = (i-1) * 10 + 1
				local e = s + 9
				r, err = p:parse(doc:sub(s, e))
			until not r

			assert.equal("unparsed buffer too large", err)
			assert.falsy(r)
		end)

	end)

end)
