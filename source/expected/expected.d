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
* allows to define `Expected` without value (`void` for `T`)
* provides facility to change the `Expected` behavior by custom `Hook` implementation using the Design by introspection.

License: BSL-1.0
Author: Tomáš Chaloupka
+/

//TODO: collect errno function call - see https://dlang.org/phobos/std_exception.html#ErrnoException
//TODO: documentation and usage examples
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
				//TODO: Hook to disallow reassign
				destroyStorage();
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

	/++ Calculates the hash value of the `Expected` in a way that iff it has a value,
		it returns hash of the value.
		Hash is computed using internal state and storage of the `Expected` otherwise.
	+/
	size_t toHash()() const nothrow
	{
		static if (!is(T == void)) { if (hasValue) return value.hashOf; }
		return storage.hashOf(state);
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
		@property ref inout(T) value() inout
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
	@property ref inout(E) error() inout
	{
		assert(state != State.empty);
		assert(state == State.error);

		return trustedGetError;
	}

	// range interface
	static if (!is(T == void))
	{
		/++ Range interface defined by `empty`, `front`, `popFront`.
			Yields one value if `Expected` has value.

			If `T == void`, range interface isn't defined.
		+/
		@property bool empty() const { return state != State.value; }

		/// ditto
		@property ref inout(T) front() inout { return value; }

		/// ditto
		void popFront() { destroyStorage(); state = State.empty; }
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
				@disable this(const(CT) val) const;
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

	void destroyStorage()()
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
Expected!(T, E, Hook) expected(E = string, Hook = Abort, T)(T value)
{
	return Expected!(T, E, Hook)(value);
}

/// ditto
Expected!(void, E, Hook) expected(E = string, Hook = Abort)()
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

/++ Constructs `Expected` from the result of the provided function.

	If the function is `nothrow`, it just returns it's result using `expected`.

	If not, then it uses `try catch` block and constructs `Expected` with value or error.
+/
template expected(alias fun, Hook = Abort)
{
	auto expected(Args...)(auto ref Args args) if (is(typeof(fun(args))))
	{
		import std.traits : hasFunctionAttributes;

		alias T = typeof(fun(args));
		static if (is(hasFunctionAttributes!(fun, "nothrow"))) return expected!Exception(fun(args));
		else
		{
			try return Expected!(T, Exception)(fun(args));
			catch (Exception ex) return unexpected!T(ex);
		}
	}
}

///
unittest
{
	auto fn(int v) { if (v == 42) throw new Exception("don't panic"); return v; }

	assert(expected!fn(1) == 1);
	assert(expected!fn(42).error.msg == "don't panic");
}

/++
	Creates an `Expected` object from an error value, with type inference.
+/
Expected!(T, E, Hook) unexpected(T = void, Hook = Abort, E)(E err)
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

/++
	Returns the error contained within the `Expected` _and then_ another value if there's no error.
	This function can be used for control flow based on `Expected` values.

	Params:
		exp = The `Expected` to call andThen on
		value = The value to return if there isn't an error
		pred = The predicate to call if the there isn't an error
+/
auto ref EX andThen(EX)(auto ref EX exp, lazy EX value)
	if (is(EX : Expected!(T, E, H), T, E, H))
{
	return exp.andThen!value;
}

/// ditto
auto ref EX andThen(alias pred, EX)(auto ref EX exp)
	if (
		is(EX : Expected!(T, E, H), T, E, H)
		&& is(typeof(pred()) : EX)
	)
{
	return exp.hasError ? exp : pred();
}

///
unittest
{
	assert(expected(42).andThen(expected(1)) == 1);
	assert(expected(42).andThen!(() => expected(0)) == 0);
	assert(expected(42).andThen(unexpected!int("foo")).error == "foo");
	assert(expected(42).andThen!(() => unexpected!int("foo")).error == "foo");
	assert(unexpected!int("foo").andThen(expected(42)).error == "foo");
	assert(unexpected!int("foo").andThen!(() => expected(42)).error == "foo");
	assert(unexpected!int("foo").andThen(unexpected!int("bar")).error == "foo");
	assert(unexpected!int("foo").andThen!(() => unexpected!int("bar")).error == "foo");

	// with void value
	assert(expected().andThen!(() => expected()));
	assert(expected().andThen!(() => unexpected("foo")).error == "foo");
	assert(unexpected("foo").andThen!(() => expected()).error == "foo");
}

/++
	Returns the value contained within the `Expected` _or else_ another value if there's an error.
	This function can be used for control flow based on `Expected` values.

	Params:
		exp = The `Expected` to call orElse on
		value = The value to return if there is an error
		pred = The predicate to call if the there is an error
+/
U orElse(EX, U)(auto ref EX exp, lazy U value)
	if (is(EX : Expected!(T, E, H), T, E, H) && is(U : T))
{
	return exp.orElse!value;
}

/// ditto
auto ref orElse(alias pred, EX)(auto ref EX exp)
	if (is(EX : Expected!(T, E, H), T, E, H) && is(typeof(pred()) : T))
{
	return exp.hasError ? pred() : exp.value;
}

/// ditto
auto ref orElse(alias pred, EX)(auto ref EX exp)
	if (
		is(EX : Expected!(T, E, H), T, E, H)
		&& is(typeof(pred()) : Expected!(T, E, H))
	)
{
	return exp.hasError ? pred() : exp;
}

///
unittest
{
	assert(expected(42).orElse(0) == 42);
	assert(expected(42).orElse!(() => 0) == 42);
	assert(unexpected!int("foo").orElse(0) == 0);
	assert(unexpected!int("foo").orElse!(() => 0) == 0);
	assert(expected(42).orElse!(() => expected(0)) == 42);
	assert(unexpected!int("foo").orElse!(() => expected(42)) == 42);
	assert(unexpected!int("foo").orElse!(() => unexpected!int("bar")).error == "bar");

	// with void value
	assert(expected().orElse!(() => unexpected("foo")));
	assert(unexpected("foo").orElse!(() => expected()));
	assert(unexpected("foo").orElse!(() => unexpected("bar")).error == "bar");
}

/++
	Applies a function to the expected value in an `Expected` object.

	If no expected value is present, the original error value is passed through
	unchanged, and the function is not called.

	Params:
		op = function called to map `Expected` value
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template map(alias op, Hook = Abort)
{
	/++
		The actual `map` function.

		Params:
			self = an [Expected] object
	+/
	auto map(T, E, H)(auto ref Expected!(T, E, H) self)
		if ((is(T == void) && is(typeof(op()))) || (!is(T == void) && is(typeof(op(self.value)))))
	{
		static if (is(T == void)) alias U = typeof(op());
		else alias U = typeof(op(self.value));

		if (self.hasError) return unexpected!(U, Hook)(self.error);
		else
		{
			static if (is(T == void)) return expected!(E, Hook)(op());
			else return expected!(E, Hook)(op(self.value));
		}
	}
}

///
unittest
{
	{
		assert(expected(42).map!((a) => a/2).value == 21);
		assert(expected().map!(() => 42).value == 42);
		assert(unexpected!int("foo").map!((a) => 42).error == "foo");
		assert(unexpected("foo").map!(() => 42).error == "foo");
	}

	// remap hook
	{
		static struct Hook {}
		auto res = expected(42).map!((a) => a/2, Hook);
		assert(res == 21);
		static assert(is(typeof(res) == Expected!(int, string, Hook)));
	}
}

/++
	Applies a function to the expected error in an `Expected` object.

	If no error is present, the original value is passed through
	unchanged, and the function is not called.

	Params:
		op = function called to map `Expected` error
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template mapError(alias op, Hook = Abort)
{
	/++
		The actual `mapError` function.

		Params:
			self = an [Expected] object
	+/
	auto mapError(T, E, H)(auto ref Expected!(T, E, H) self)
		if (is(typeof(op(self.error))))
	{
		alias U = typeof(op(self.error));

		static if (!is(T == void))
		{
			if (self.hasValue) return expected!(U, Hook)(self.value);
		}
		return unexpected!(T, Hook)(op(self.error));
	}
}

///
unittest
{
	{
		assert(expected(42).mapError!((e) => e).value == 42);
		assert(unexpected("foo").mapError!((e) => 42).error == 42);
		assert(unexpected("foo").mapError!((e) => new Exception(e)).error.msg == "foo");
	}

	// remap hook
	{
		static struct Hook {}
		auto res = expected(42).mapError!((e) => e, Hook);
		assert(res == 42);
		static assert(is(typeof(res) == Expected!(int, string, Hook)));

		auto res2 = unexpected!int("foo").mapError!((e) => "bar", Hook);
		assert(res2.error == "bar");
		static assert(is(typeof(res2) == Expected!(int, string, Hook)));
	}
}

/++
	Maps a `Expected<T, E>` to `U` by applying a function to a contained value, or a fallback function to a contained error value.

	Both functions has to be of the same return type.

	This function can be used to unpack a successful result while handling an error.

	Params:
		valueOp = function called to map `Expected` value
		errorOp = function called to map `Expected` error
		hook = use another hook for mapped `Expected`

	Returns:
		A new `Expected` object containing the result.
+/
template mapOrElse(alias valueOp, alias errorOp)
{
	/++
		The actual `mapOrElse` function.

		Params:
			self = an [Expected] object
	+/
	auto mapOrElse(T, E, H)(auto ref Expected!(T, E, H) self)
		if (
			is(typeof(errorOp(self.error))) &&
			(
				(is(T == void) && is(typeof(valueOp()) == typeof(errorOp(self.error)))) ||
				(!is(T == void) && is(typeof(valueOp(self.value)) == typeof(errorOp(self.error))))
			)
		)
	{
		alias U = typeof(errorOp(self.error));

		if (self.hasError) return errorOp(self.error);
		else
		{
			static if (is(T == void)) return valueOp();
			else return valueOp(self.value);
		}
	}
}

unittest
{
	assert(expected(42).mapOrElse!((v) => v/2, (e) => 0) == 21);
	assert(expected().mapOrElse!(() => true, (e) => false));
	assert(unexpected!int("foo").mapOrElse!((v) => v/2, (e) => 42) == 42);
	assert(!unexpected("foo").mapOrElse!(() => true, (e) => false));
}

// -- global tests --

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
	res.value = 43;
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
	static assert(!__traits(compiles, res.value = res.value));
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
	static assert(!__traits(compiles, res.value = res.value));
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

//FIXME: doesn't work - some older dmd error
static if (__VERSION__ >= 2082)
{
	// toHash
	unittest
	{
		assert(expected(42).hashOf == 42.hashOf);
		assert(expected(42).hashOf != 43.hashOf);
		assert(expected(42).hashOf == expected(42).hashOf);
		assert(expected(42).hashOf != expected(43).hashOf);
		assert(expected(42).hashOf == expected!bool(42).hashOf);
		assert(expected(42).hashOf != unexpected("foo").hashOf);
		assert(unexpected("foo").hashOf == unexpected("foo").hashOf);
	}
}

/// range interface
unittest
{
	{
		auto r = expected(42);
		assert(!r.empty);
		assert(r.front == 42);
		r.popFront();
		assert(r.empty);
	}

	{
		auto r = unexpected!int("foo");
		assert(r.empty);
	}

	{
		auto r = unexpected("foo");
		static assert(!__traits(compiles, r.empty));
		static assert(!__traits(compiles, r.front));
		static assert(!__traits(compiles, r.popFront));
	}
}
