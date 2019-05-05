/++
This module is implementing the Expected idiom.

See the (Andrei Alexandrescu’s talk (Systematic Error Handling in C++)[http://channel9.msdn.com/Shows/Going+Deep/C-and-Beyond-2012-Andrei-Alexandrescu-Systematic-Error-Handling-in-C]
and (its slides)[https://skydrive.live.com/?cid=f1b8ff18a2aec5c5&id=F1B8FF18A2AEC5C5!1158].

Or more recent ["Expect the Expected"](https://www.youtube.com/watch?v=nVzgkepAg5Y) by Andrei Alexandrescu for further background.

It is also inspired by C++'s proposed [std::expected](https://wg21.link/p0323).

Similar work is (expectations)[http://code.dlang.org/packages/expectations] by Paul Backus.

Main differences with that are:

* lightweight, no other external dependencies
* allows to use same types for `T` and `E`
* provides facility to change the `Expected` behavior by custom `Hook` implementation using the Design by introspection.

License: BSL-1.0
Author: Tomáš Chaloupka
+/

//TODO: unwrap a unexpect?
//TODO: map, bind, then
//TODO: toHash
//TODO: catchError
//TODO: swap
//TODO: collect - wraps the method with try/catch end returns Expected: see https://dlang.org/phobos/std_exception.html#collectException
//      or maybe use then or expected for that and behave based on the result type and nothrow
//TODO: collect errno function call - see https://dlang.org/phobos/std_exception.html#ErrnoException
//TODO: usage examples
//TODO: ability to enforce error handling (via refcounted payload)

module expected;

version (unittest) import std.exception : assertThrown;

@safe:

/++
	TODO: docs

	The default type for the error value is `string`.

	Params:
		T    = represents the expected value
		E    = represents the reason explaining why it doesn’t contains avalue of type T, that is the unexpected value.
		Hook = defines the `Expected` type behavior
+/
struct Expected(T, E = string, Hook = Abort)
	if (!is(E == void))
{
	import std.functional: forward;
	import std.meta : AliasSeq, Erase, NoDuplicates;
	import std.traits: hasElaborateDestructor, isAssignable, isCopyable, Unqual;
	import std.typecons : Flag, No, Yes;

	private alias Types = NoDuplicates!(Erase!(void, AliasSeq!(T, E)));

	static foreach (i, T; Types)
	{
		/++
			Constructs an `Expected` with value or error based on the tye of the provided.

			In case when `T == E`, it constructs `Expected` with value.

			In case when `T == void`, it constructs `Expected` with error value.

			Default constructor (if enabled) initializes `Expected` to `T.init` value.
			If `T == void`, it initializes `Expected` with no error.
		+/
		this()(auto ref T val)
		{
			static if (isCopyable!T) storage = Storage(val);
			else storage = Storage(forward!val);
			setState!(T, Yes.force)();
		}

		static if (isCopyable!T)
		{
			/// ditto
			this()(auto ref const(T) val) const
			{
				storage = const(Storage)(val);
				setState!(T, Yes.force)();
			}

			/// ditto
			this()(auto ref immutable(T) val) immutable
			{
				storage = immutable(Storage)(val);
				setState!(T, Yes.force)();
			}
		}
		else
		{
			@disable this(const(T) val) const;
			@disable this(immutable(T) val) immutable;
		}
	}

	// generate constructor with flag to determine type of value
	static if (Types.length == 1 && !is(T == void))
	{
		/++ Constructs an `Expected` with value or error based on the provided flag.
			This constructor is available only for cases when value and error has the same type,
			so we can still construct `Expected` with value or error.

			Params:
				val     = Value to set as value or error
				success = If `true`, `Expected` with value is created, `Expected` with error otherwise.
		+/
		this()(auto ref E val, bool success)
		{
			static if (isCopyable!T) storage = Storage(val);
			else storage = Storage(forward!val);
			setState!E(success ? State.value : State.error);
		}

		static if (isCopyable!E)
		{
			/// ditto
			this()(auto ref const(E) val, bool success) const
			{
				storage = const(Storage)(val);
				setState!E(success ? State.value : State.error);
			}

			/// ditto
			this()(auto ref immutable(E) val, bool success) immutable
			{
				storage = immutable(Storage)(val);
				setState!E(success ? State.value : State.error);
			}
		}
		else
		{
			@disable this(const(E) val, bool success) const;
			@disable this(immutable(E) val, bool success) immutable;
		}
	}

	static if (__traits(hasMember, Hook, "enableDefaultConstructor"))
	{
		static assert(
			is(typeof(__traits(getMember, Hook, "enableDefaultConstructor")) : bool),
			"Hook's enableDefaultConstructor is expected to be of bool value"
		);
		static if (!__traits(getMember, Hook, "enableDefaultConstructor")) @disable this();
	}

	static foreach (i, CT; Types)
	{
		//TODO: Hook to disallow opAssign completely
		static if (isAssignable!CT)
		{
			/// Assigns a value or error to an `Expected`.
			void opAssign()(auto ref CT rhs)
			{
				static foreach (i, CT; Types)
				{
					static if (hasElaborateDestructor!CT)
					{
						static if (Types.length == 1) { if (state != State.empty) destroy.storage.values[0]; }
						else static if (i == 0) { if (state == State.value) destroy(storage.values[0]); }
						else { if (state == State.error) destroy(storage.values[1]); }
					}
				}

				//TODO: Hook to disallow reassign

				storage = Storage(forward!rhs);
				setState!CT();
			}
		}
	}

	/++ Implicit conversion to bool.
		Returns: `true` if there is no error set, `false` otherwise.
	+/
	bool opCast(T)() const if (is(T == bool)) { return !this.hasError; }

	static if (!is(T == void))
	{
		/++ Checks whether this `Expected` object contains a specific expected value.

			* `opEquals` for the value is available only when `T != void`.
			* `opEquals` for the error isn't available, use equality test for `Expected` in that case.
		+/
		bool opEquals()(const auto ref T rhs) const
		{
			return hasValue && value == rhs;
		}
	}

	/// Checks whether this `Expected` object and `rhs` contain the same expected value or error value.
	bool opEquals()(const auto ref Expected!(T, E, Hook) rhs) const
	{
		if (state != rhs.state) return false;
		static if (!is(T == void)) { if (hasValue) return value == rhs.value; }
		return error == rhs.error;
	}

	static if (!is(T == void))
	{
		/// Checks if `Expected` has value
		@property bool hasValue()() const { return state == State.value; }

		/++
			Returns the expected value if there is one. Otherwise, throws an
			exception or asserts (based on the provided `Hook` implementation).
			In case there is no value nor error specified, it asserts.

			Throws:
				If `E` inherits from `Throwable`, the error value is thrown.
				Otherwise, an [Unexpected] instance containing the error value is
				thrown.
		+/
		@property inout(T) value() inout
		{
			//TODO: hook
			assert(state != State.empty);
			assert(state == State.value);
			// static if (is(E : Throwable)) throw error();
			// else throw new Unexpected!E(error());

			return trustedGetValue();
		}
	}

	/// Checks if `Expected` has error
	@property bool hasError()() const { return state == State.error; }

	/++
		Returns the error value. May only be called when `hasValue` returns `false`.
	+/
	inout(E) error() inout
	{
		assert(state != State.empty);
		assert(state == State.error);

		return trustedGetError;
	}

	private:

	union Storage
	{
		Types values;

		// generate storage constructors
		static foreach (i, CT; Types)
		{
			@trusted this()(auto ref CT val)
			{
				static if (isCopyable!CT) __traits(getMember, Storage, "values")[i] = val;
				else __traits(getMember, Storage, "values")[i] = forward!val;
			}

			static if (isCopyable!CT)
			{
				@trusted this()(auto ref const(CT) val) const { __traits(getMember, Storage, "values")[i] = val; }
				@trusted this()(auto ref immutable(CT) val) immutable { __traits(getMember, Storage, "values")[i] = val; }
			}
			else
			{
				@disable this(const(TC) val) const;
				@disable this(immutable(CT) val) immutable;
			}
		}
	}

	@trusted
	ref inout(E) trustedGetError()() inout
	{
		static if (Types.length == 1) return __traits(getMember, storage, "values")[0];
		else return __traits(getMember, storage, "values")[1];
	}

	static if (!is(T == void))
	{
		ref inout(T) trustedGetValue()() inout
		{
			return __traits(getMember, storage, "values")[0];
		}
	}

	enum State : ubyte { empty, value, error }

	Storage storage;
	static if (is(T == void)) State state = State.empty;
	else State state = State.value;

	void setState(MT, Flag!"force" force = No.force)()
	{
		State s;
		static if (Types.length == 1 && is(T == void)) s = State.error;
		else static if (Types.length == 1 || is(MT == T)) s = State.value;
		else s = State.error;

		static if (!force)
		{
			//TODO: change with Hook?
			assert(state == State.empty || state == s, "Can't change meaning of already set Expected type");
		}

		state = s;
	}
}

/++ TODO
+/
struct Abort
{
static:
	immutable bool enableDefaultConstructor = true;
}

/// An exception that represents an error value.
class Unexpected(T) : Exception
{
	T error; /// error value

	/// Constructs an `Unexpected` exception from an error value.
	pure @safe @nogc nothrow
	this(T value, string file = __FILE__, size_t line = __LINE__)
	{
		super("Unexpected error", file, line);
		this.error = error;
	}
}

/++
	Creates an `Expected` object from an expected value, with type inference.
+/
Expected!(T, E) expected(E = string, Hook = Abort, T)(T value)
{
	return Expected!(T, E, Hook)(value);
}

/// ditto
Expected!(void, E) expected(E = string, Hook = Abort)()
{
	return Expected!(void, E, Hook)();
}

// expected
unittest
{
	// void
	{
		auto res = expected();
		static assert(is(typeof(res) == Expected!(void, string)));
		assert(res);
	}

	// int
	{
		auto res = expected(42);
		static assert(is(typeof(res) == Expected!(int, string)));
		assert(res);
		assert(res.value == 42);
	}

	// string
	{
		auto res = expected("42");
		static assert(is(typeof(res) == Expected!(string, string)));
		assert(res);
		assert(res.value == "42");
	}

	// other error type
	{
		auto res = expected!bool(42);
		static assert(is(typeof(res) == Expected!(int, bool)));
		assert(res);
		assert(res.value == 42);
	}
}

/++
	Creates an `Expected` object from an error value, with type inference.
+/
Expected!(T, E) unexpected(T = void, Hook = Abort, E)(E err)
{
	static if (Expected!(T, E, Hook).Types.length == 1 && !is(T == void))
		return Expected!(T, E, Hook)(err, false);
	else return Expected!(T, E, Hook)(err);
}

//unexpected
unittest
{
	// implicit void value type
	{
		auto res = unexpected("foo");
		static assert(is(typeof(res) == Expected!(void, string)));
		assert(!res);
		assert(res.error == "foo");
	}

	// bool
	{
		auto res = unexpected!int("42");
		static assert(is(typeof(res) == Expected!(int, string)));
		assert(!res);
		assert(res.error == "42");
	}

	// other error type
	{
		auto res = unexpected!bool(42);
		static assert(is(typeof(res) == Expected!(bool, int)));
		assert(!res);
		assert(res.error == 42);
	}
}

// Expected.init
@system nothrow unittest
{
	auto res = Expected!(int, string).init;
	assert(res.hasValue && !res.hasError);
	assert(res);
	assert(res.value == int.init);
	assertThrown!Throwable(res.error);
}

// Default constructor - disabled
unittest
{
	static struct DisableDefaultConstructor { static immutable bool enableDefaultConstructor = false; }
	static assert(!__traits(compiles, Expected!(int, string, DisableDefaultConstructor)()));
}

// Default constructor - enabled
@system nothrow unittest
{
	auto res = Expected!(int, string)();
	assert(res.hasValue && !res.hasError);
	assert(res);
	assert(res.value == int.init);
	assertThrown!Throwable(res.error);
}

// Default types
nothrow @nogc unittest
{
	auto res = Expected!(int)(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
	res = 43;
	assert(res.value == 43);
}

// Default types with const payload
nothrow @nogc unittest
{
	alias Exp = Expected!(const(int));
	static assert(is(typeof(Exp.init.value) == const(int)));
	auto res = Exp(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
}

// Default types with immutable payload
unittest
{
	alias Exp = Expected!(immutable(int));
	static assert(is(typeof(Exp.init.value) == immutable(int)));
	auto res = Exp(42);
	assert(res);
	assert(res.hasValue && !res.hasError);
	assert(res.value == 42);
}

// opAssign
@system nothrow unittest
{
	// value
	{
		auto res = Expected!(int, string).init;
		res = 42;
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		res = 43;
		assertThrown!Throwable(res = "foo");
	}

	// error
	{
		auto res = Expected!(int, string)("42");
		assert(!res.hasValue && res.hasError);
		assert(res.error == "42");
		res = "foo";
		assert(res.error == "foo");
		assertThrown!Throwable(res = 42);
	}
}

/// Same types
@system nothrow unittest
{
	{
		alias Exp = Expected!(int, int);
		auto res = Exp(42);
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error());
	}

	// const mix
	{
		alias Exp = Expected!(const(int), int);
		auto res = Exp(const int(42));
		auto val = res.value;
		static assert(is(typeof(val) == const int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}

	// const mix
	{
		alias Exp = Expected!(const(int), int);
		auto res = Exp(42);
		auto err = res.error;
		static assert(is(typeof(err) == int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix
	{
		alias Exp = Expected!(immutable(int), int);
		auto res = Exp(immutable int(42));
		auto val = res.value;
		static assert(is(typeof(val) == immutable int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}

	// immutable mix
	{
		alias Exp = Expected!(immutable(int), int);
		auto res = Exp(42);
		auto err = res.error;
		static assert(is(typeof(err) == int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix reverse
	{
		alias Exp = Expected!(int, immutable(int));
		auto res = Exp(immutable int(42));
		auto err = res.error;
		static assert(is(typeof(err) == immutable int));
		assert(!res);
		assert(!res.hasValue && res.hasError);
		assert(res.error == 42);
		assertThrown!Throwable(res.value);
	}

	// immutable mix reverse
	{
		alias Exp = Expected!(int, immutable(int));
		auto res = Exp(42);
		auto val = res.value;
		static assert(is(typeof(val) == int));
		assert(res);
		assert(res.hasValue && !res.hasError);
		assert(res.value == 42);
		assertThrown!Throwable(res.error);
	}
}

// void payload
nothrow @nogc unittest
{
	alias Exp = Expected!(void, int);
	static assert (!__traits(hasMember, Exp, "hasValue"));
	static assert (!__traits(hasMember, Exp, "value"));

	{
		auto res = Exp();
		assert(res);
		assert(!res.hasError);
	}

	{
		auto res = Exp(42);
		assert(!res);
		assert(res.hasError);
		assert(res.error == 42);
	}
}

// opEquals
unittest
{
	assert(expected(42) == 42);
	assert(expected(42) != 43);
	assert(expected("foo") == "foo");
	assert(expected("foo") != "bar");
	assert(expected("foo") == cast(const string)"foo");
	assert(expected("foo") == cast(immutable string)"foo");
	assert(expected(42) == expected(42));
	assert(expected(42) != expected(43));
	assert(expected(42) != unexpected!int("42"));

	static assert(!__traits(compiles, unexpected("foo") == "foo"));
	assert(unexpected(42) == unexpected(42));
	assert(unexpected(42) != unexpected(43));
	assert(unexpected("foo") == unexpected("foo"));
	assert(unexpected("foo") != unexpected("bar"));
}
