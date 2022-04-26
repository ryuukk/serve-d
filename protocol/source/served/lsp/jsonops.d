module served.lsp.jsonops;

import std.json : StdJSONValue = JSONValue;

public import mir.algebraic_alias.json : JsonValue = JsonAlgebraic, StringMap;

deprecated("use serializeJson") StdJSONValue toJSON(T)(T value)
{
	return parseJSON(serializeJson(value));
}

deprecated("use deserializeJson") T fromJSON(T)(StdJSONValue value)
{
	return deserializeJson!T(value.toString);
}

/++
JSON serialization function.
+/
string serializeJson(T)(auto ref T value)
{
	import mir.ser.json : serializeJson;

	return serializeJson!T(value);
}

T deserializeJson(T)(scope const(char)[] text)
{
	import mir.deser.json : deserializeDynamicJson;

	return deserializeDynamicJson!T(text);
}

unittest
{
	string[] tests = [
		`{"hello":"world"}`,
		`{"a":[1,"world",false,null]}`,
		`null`,
		`5`,
		`"ok"`,
		`["ok",[[[[[false]]]]]]`,
		`true`,
	];

	foreach (v; tests)
	{
		assert(v.deserializeJson!JsonValue.serializeJson == v);
	}
}

T jsonValueTo(T)(scope JsonValue value)
{
	return value.serializeJson.deserializeJson!T;
}

JsonValue toJsonValue(StdJSONValue value)
{
	import std.json : JSONType;

	final switch (value.type)
	{
	case JSONType.object:
		StringMap!JsonValue ret;
		foreach (key, val; value.object)
			ret[key] = val.toJsonValue;
		return JsonValue(ret);
	case JSONType.array:
		JsonValue[] ret = new JsonValue[value.array.length];
		foreach (i, val; value.array)
			ret[i] = val.toJsonValue;
		return JsonValue(ret);
	case JSONType.true_:
		return JsonValue(true);
	case JSONType.false_:
		return JsonValue(false);
	case JSONType.null_:
		return JsonValue(null);
	case JSONType.string:
		return JsonValue(value.str);
	case JSONType.float_:
		return JsonValue(value.floating);
	case JSONType.integer:
		return JsonValue(value.integer);
	case JSONType.uinteger:
		return JsonValue(value.uinteger);
	}
}

JsonValue toJsonValue(T)(auto ref T value)
{
	return value.serializeJson.deserializeJson!JsonValue;
}

private const(char)[] skipString(ref scope return const(char)[] jsonObject)
in(jsonObject.length)
in(jsonObject.ptr[0] == '"')
{
	auto start = jsonObject.ptr;
	jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	int escape;
	while (jsonObject.length)
	{
		char c = jsonObject.ptr[0];
		if (escape)
		{
			if (c == 'u')
				escape += 4;
			escape--;
		}
		else
		{
			if (c == '"')
				break;
			else if (c == '\\')
				escape = 1;
		}
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	}
	if (!jsonObject.length || jsonObject.ptr[0] != '"')
		throw new Exception("malformed JSON string");
	jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	return start[0 .. jsonObject.ptr - start];
}

private const(char)[] skipNumber(ref scope return const(char)[] jsonObject)
in(jsonObject.length)
{
	import std.ascii : isDigit;

	auto start = jsonObject.ptr;
	if (jsonObject.ptr[0] == '-')
	{
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
		if (!jsonObject.length)
			throw new Exception("malformed JSON number");
	}

	while (jsonObject.length && jsonObject.ptr[0].isDigit)
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];

	if (jsonObject.length && jsonObject.ptr[0] == '.')
	{
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
		if (!jsonObject.length)
			throw new Exception("malformed JSON number");

		while (jsonObject.length && jsonObject.ptr[0].isDigit)
			jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	}

	if (jsonObject.length && (jsonObject.ptr[0] == 'e' || jsonObject.ptr[0] == 'E'))
	{
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
		if (!jsonObject.length)
			throw new Exception("malformed JSON number");

		if (jsonObject.ptr[0] == '-' || jsonObject.ptr[0] == '+')
		{
			jsonObject = jsonObject.ptr[1 .. jsonObject.length];
			if (!jsonObject.length)
				throw new Exception("malformed JSON number");
		}

		while (jsonObject.length && jsonObject.ptr[0].isDigit)
			jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	}

	return start[0 .. jsonObject.ptr - start];
}

private const(char)[] skipLiteral(ref scope return const(char)[] jsonObject, string literal)
{
	if (jsonObject.length < literal.length
		|| jsonObject.ptr[0 .. literal.length] != literal)
		throw new Exception("expected literal '" ~ literal
			~ "', but got '" ~ jsonObject.idup ~ "'");

	auto ret = jsonObject.ptr[0 .. literal.length];
	jsonObject = jsonObject.ptr[literal.length .. jsonObject.length];
	return ret;
}

// skips until matching level of start/end tokens - skips strings
private const(char)[] skipByPairs(char start, char end, string name)(ref scope return const(char)[] jsonObject)
in(jsonObject.length)
in(jsonObject.ptr[0] == start)
{
	auto startPtr = jsonObject.ptr;
	int depth = 0;
	Loop: do
	{
		switch (jsonObject.ptr[0])
		{
		case start:
			depth++;
			break;
		case end:
			depth--;
			break;
		case '"':
			jsonObject.skipString();
			continue Loop;
		default:
			break;
		}
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
	} while (depth && jsonObject.length);

	if (depth != 0)
		throw new Exception("malformed JSON " ~ name);
	return startPtr[0 .. jsonObject.ptr - startPtr];
}

private const(char)[] skipObject(ref scope return const(char)[] jsonObject)
{
	return jsonObject.skipByPairs!('{', '}', "object");
}

private const(char)[] skipArray(ref scope return const(char)[] jsonObject)
{
	return jsonObject.skipByPairs!('[', ']', "array");
}

private const(char)[] skipValue(ref scope return const(char)[] jsonObject)
{
	if (!jsonObject.length)
		return null;
	switch (jsonObject.ptr[0])
	{
	case '"': // string
		return jsonObject.skipString();
	case '-': // number
	case '0': .. case '9': // number
		return jsonObject.skipNumber();
	case 't': // true
		return jsonObject.skipLiteral("true");
	case 'f': // false
		return jsonObject.skipLiteral("false");
	case 'n': // null
		return jsonObject.skipLiteral("null");
	case '{': // object
		return jsonObject.skipObject();
	case '[': // array
		return jsonObject.skipArray();
	default:
		return null;
	}
}

private void skipWhite(ref scope return const(char)[] jsonObject)
{
	import std.string : stripLeft;

	jsonObject = jsonObject.stripLeft;
}

auto parseKeySlices(fields...)(scope return const(char)[] jsonObject)
in (jsonObject.length)
in (jsonObject[0] == '{')
in (jsonObject[$ - 1] == '}')
{
	import std.string : representation;
	import std.algorithm : canFind;

	mixin(`struct Ret {
		union {
			const(char)[][fields.length] _arr;
			struct {
				`, (){
					string fieldsStr;
					foreach (string field; fields)
						fieldsStr ~= "const(char)[] " ~ field ~ ";\n";
					return fieldsStr;
				}(), `
			}
		}
	}`);

	Ret ret;

	jsonObject = jsonObject[1 .. $ - 1];
	jsonObject.skipWhite();
	while (jsonObject.length)
	{
		auto key = jsonObject.skipValue();
		if (key.length < 2 || key.ptr[0] != '"' || key.ptr[key.length - 1] != '"')
			throw new Exception("malformed JSON object key");
		jsonObject.skipWhite();
		if (!jsonObject.length || jsonObject.ptr[0] != ':')
			throw new Exception("malformed JSON");
		jsonObject = jsonObject.ptr[1 .. jsonObject.length];
		jsonObject.skipWhite();
		auto value = jsonObject.skipValue();
		jsonObject.skipWhite();

		if (jsonObject.length)
		{
			if (jsonObject.ptr[0] != ',')
				throw new Exception("malformed JSON");
			jsonObject = jsonObject.ptr[1 .. jsonObject.length];
			jsonObject.skipWhite();
		}

		RawKeySwitch: switch (key)
		{
			static foreach (string field; fields)
			{
			case '"' ~ field ~ '"':
				mixin("ret.", field, " = value;");
				break RawKeySwitch;
			}
			default:
				if (key.representation.canFind('\\'))
				{
					// wtf escaped key
					DeserializedSwitch: switch (key.deserializeJson!string)
					{
						static foreach (string field; fields)
						{
						case field:
							mixin("ret.", field, " = value;");
							break DeserializedSwitch;
						}
						default:
							break; // not part of wanted keys
					}
				}
				break; // not part of wanted keys
		}
	}

	return ret;
}

///
unittest
{
	string json = `{
		"hello": "ther\"e",
		"foo": {"ok":"cool"} ,
		"bar": [1, 2.0,3],
		"extra": {
			"f": [
				1 , {
					"a": "b",
					"c": false
				}, {
					"f": [1, {
						"a": "b",
						"c": false
					}],
					"a": 10000
				}
			],
			"a": 10000
		},
		"yes": true,
		"no": false,
		"opt": null
	}`;
	auto parts = json.parseKeySlices!("hello", "foo", "bar", "extra", "yes", "opt", "notinjson");
	assert(!parts.notinjson.length);
	assert(parts.hello is json[13 .. 22]);
	assert(parts.foo is json[33 .. 46]);
	assert(parts.bar is json[58 .. 68]);
	assert(parts.extra is json[81 .. 246]);
	assert(parts.yes is json[257 .. 261]);
	assert(parts.opt is json[287 .. 291]);
}

void visitJsonArray(alias fn)(scope const(char)[] jsonArray)
in (jsonArray.length)
in (jsonArray[0] == '[')
in (jsonArray[$ - 1] == ']')
{
	jsonArray = jsonArray[1 .. $ - 1];
	jsonArray.skipWhite();
	while (jsonArray.length)
	{
		auto value = jsonArray.skipValue();
		fn(value);
		jsonArray.skipWhite();
		if (jsonArray.length)
		{
			if (jsonArray.ptr[0] != ',')
				throw new Exception("malformed JSON array");
			jsonArray = jsonArray.ptr[1 .. jsonArray.length];
			jsonArray.skipWhite();
		}
	}
}

unittest
{
	string json = `["the[r\"e",
		{"ok":"cool"} ,
		[1, 2.0,3],
		{
			"f": [
				1 , {
					"a": "b",
					"c": false
				}, {
					"f": [1, {
						"a": "b",
						"c": false
					}],
					"a": 10000
				}
			],
			"a": 10000
		},
		true,
		false,
		null
	]`;
	string[] expected = [
		json[1 .. 11],
		json[15 .. 28],
		json[33 .. 43],
		json[47 .. 212],
		json[216 .. 220],
		json[224 .. 229],
		json[233 .. 237],
	];
	int i;
	json.visitJsonArray!((item) {
		assert(expected[i++] is item);
	});
	assert(i == expected.length);
}
