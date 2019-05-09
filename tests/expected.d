module tests.expected;

import expected;
import std.exception;

@safe:

@("Expected.init")
@system nothrow unittest
{
    struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }

    {
        auto res = Expected!(int, string).init;
        assert(!res.hasValue && !res.hasError);
        assert(res);
        assertThrown!Throwable(res.value);
        assertThrown!Throwable(res.error);
        static assert(!__traits(compiles, res = 42));
    }

    {
        auto res = Expected!(int, string, EnableDefaultConstructor).init;
        assert(!res.hasValue && !res.hasError);
        assert(res);
        assert(res.value == 0);
        assert(res.error is null);
        res = 42;
        assert(res.value == 42);
    }

    // T == void
    {
        auto res = Expected!(void, string).init;
        static assert(!__traits(compiles, res.hasValue));
        static assert(!__traits(compiles, res.value));
        static assert(!__traits(compiles, res = "foo"));
        assert(!res.hasError);
        assert(res);
        assertThrown!Throwable(res.error);
    }

    // T == void
    {
        auto res = Expected!(void, string, EnableDefaultConstructor).init;
        static assert(!__traits(compiles, res.hasValue));
        static assert(!__traits(compiles, res.value));
        assert(!res.hasError);
        assert(res);
        assert(res.error is null);
        res = "foo";
        assert(res.error == "foo");
    }
}

@("Default constructor - disabled")
unittest
{
    static assert(!__traits(compiles, Expected!(int, string)()));
}

@("Default constructor - enabled")
@system nothrow unittest
{
    struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }
    {
        auto res = Expected!(int, string, EnableDefaultConstructor)();
        assert(!res.hasValue && !res.hasError);
        assert(res);
        assert(res.value == 0);
        assert(res.error is null);
        res = 42;
        assert(res);
        assert(res.value == 42);
    }

    {
        auto res = Expected!(void, string, EnableDefaultConstructor)();
        assert(!res.hasError);
        assert(res);
        assert(res.error is null);
        res = "foo";
        assert(res.hasError);
        assert(!res);
        assert(res.error == "foo");
    }
}

@("Default types")
nothrow @nogc unittest
{
    auto res = Expected!(int)(42);
    assert(res);
    assert(res.hasValue && !res.hasError);
    assert(res.value == 42);
    res.value = 43;
    assert(res.value == 43);
}

@("Default types with const payload")
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

@("Default types with immutable payload")
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

@("opAssign")
@system nothrow unittest
{
    struct EnableDefaultConstructor { static immutable bool enableDefaultConstructor = true; }
    // value
    {
        auto res = Expected!(int, string, EnableDefaultConstructor).init;
        res = 42;
        assert(res);
        assert(res.hasValue && !res.hasError);
        assert(res.value == 42);
        res = 43;
        assertThrown!Throwable(res = "foo");
    }

    // error
    {
        auto res = Expected!(int, string, EnableDefaultConstructor)("42");
        assert(!res.hasValue && res.hasError);
        assert(res.error == "42");
        res = "foo";
        assert(res.error == "foo");
        assertThrown!Throwable(res = 42);
    }
}

@("Same types")
@system nothrow unittest
{
    // value
    {
        alias Exp = Expected!(int, int);
        auto res = Exp(42);
        assert(res);
        assert(res.hasValue && !res.hasError);
        assert(res.value == 42);
        assertThrown!Throwable(res.error());
    }

    // error
    {
        alias Exp = Expected!(int, int);
        auto res = Exp(42, false);
        assert(!res);
        assert(!res.hasValue && res.hasError);
        assert(res.error == 42);
        assertThrown!Throwable(res.value());
        assert(err!int(42).error == 42);
    }

    // immutable value
    {
        alias Exp = Expected!(immutable(int), immutable(int));
        auto res = Exp(immutable int(42));
        assert(res);
        assert(res.hasValue && !res.hasError);
        assert(res.value == 42);
        assertThrown!Throwable(res.error());
    }

    // immutable error
    {
        alias Exp = Expected!(immutable(int), immutable(int));
        auto res = Exp(immutable int(42), false);
        assert(!res);
        assert(!res.hasValue && res.hasError);
        assert(res.error == 42);
        assertThrown!Throwable(res.value());
        assert(err!(immutable(int))(immutable int(42)).error == 42);
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

@("void payload")
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

@("opEquals")
unittest
{
    assert(ok(42) == 42);
    assert(ok(42) != 43);
    assert(ok("foo") == "foo");
    assert(ok("foo") != "bar");
    assert(ok("foo") == cast(const string)"foo");
    assert(ok("foo") == cast(immutable string)"foo");
    assert(ok(42) == ok(42));
    assert(ok(42) != ok(43));
    assert(ok(42) != err!int("42"));

    static assert(!__traits(compiles, err("foo") == "foo"));
    assert(err(42) == err(42));
    assert(err(42) != err(43));
    assert(err("foo") == err("foo"));
    assert(err("foo") != err("bar"));
}

//FIXME: doesn't work - some older dmd error
static if (__VERSION__ >= 2082)
{
    @("toHash")
    unittest
    {
        assert(ok(42).hashOf == 42.hashOf);
        assert(ok(42).hashOf != 43.hashOf);
        assert(ok(42).hashOf == ok(42).hashOf);
        assert(ok(42).hashOf != ok(43).hashOf);
        assert(ok(42).hashOf == ok!bool(42).hashOf);
        assert(ok(42).hashOf != err("foo").hashOf);
        assert(err("foo").hashOf == err("foo").hashOf);
    }
}

@("range interface")
unittest
{
    {
        auto r = ok(42);
        assert(!r.empty);
        assert(r.front == 42);
        r.popFront();
        assert(r.empty);
    }

    {
        auto r = err!int("foo");
        assert(r.empty);
    }

    {
        auto r = err("foo");
        static assert(!__traits(compiles, r.empty));
        static assert(!__traits(compiles, r.front));
        static assert(!__traits(compiles, r.popFront));
    }

    // with forced check
    {
        struct Hook {
            static immutable bool enableCopyConstructor = false;
            static void onUnchecked() @safe { assert(0); }
        }

        auto res = ok(42);
        assert(!res.empty);
        assert(res.front == 42);
        res.popFront(); assert(res.empty);
    }
}

@("Complex payload")
unittest
{
    {
        struct Value { int val; }

        assert(ok(Value(42)).hasValue);
        assert(ok(const Value(42)).hasValue);
        assert(ok(immutable Value(42)).hasValue);
    }

    {
        struct DisabledValue { int val; @disable this(this); }

        assert(ok(DisabledValue(42)).hasValue);
        //FIXME?
        //assert(ok(const DisabledValue(42)).hasValue);
        // assert(ok(immutable DisabledValue(42)).hasValue);
    }
}

@("RC payload")
unittest
{
    struct Hook {
        static immutable bool enableRefCountedPayload = true;
        static immutable bool enableDefaultConstructor = true;
        static void onUnchecked() pure nothrow @nogc { assert(0, "result unchecked"); }
    }

    static assert(isDefaultConstructorEnabled!Hook);

    {
        auto e = ok!(bool, Hook)(42);
        e = 43;
        assert(e.value == 43);
    }

    struct Value { int val; }

    auto res = ok!(bool, Hook)(Value(42));
    assert(res.hasValue);

    assert(ok!(bool, Hook)(true).hasValue);
    assert(err!(bool, Hook)(true).hasError);
    assert(ok!(bool, Hook)(const Value(42)).hasValue);
    assert(ok!(bool, Hook)(immutable Value(42)).hasValue);

    // same types
    assert(ok!(int, Hook)(42).value == 42);
    assert(err!(int, Hook)(42).error == 42);

    // forced check
    () @trusted {
        assertThrown!Throwable({ ok!(bool, Hook)(42); }());
    }();

    //FIXME?
    //immutable r = ok!(bool, Hook)(immutable Value(42));
    // immutable r = Expected!(immutable(Value), bool, Hook)(immutable Value(42));
    // assert(r.value == 42);
}

@("void hook")
unittest
{
    auto empty = Expected!(int, string, void).init;
    assert(!empty.hasValue);
    assert(!empty.hasError);
    assert(empty.value == int.init);
    assert(empty.error is null);
}
