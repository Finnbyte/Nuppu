// A simple hash table mapping string keys to string values.
use fmt;
use hash::fnv;

def BUCKETS: size = 64;

type hashmap = [BUCKETS][](str, str);

// Retrives the value associated with the given key in a [[hashmap]], or void if
// no such key exists.
fn get(map: *hashmap, key: str) (str | void) = {
	const hash = fnv::string(key);
	const bucket = &map[hash % len(map)];
	for (let (k, v) .. bucket) {
		if (k == key) {
			return v;
		};
	};
};

// Sets the value associated with the given key in a [[hashmap]]. Both the key
// and value are borrowed from the caller.
fn set(map: *hashmap, key: str, val: str) void = {
	const hash = fnv::string(key);
	let bucket = &map[hash % len(map)];
	for (let i = 0z; i < len(bucket); i += 1) {
		if (bucket[i].0 == key) {
			bucket[i] = (key, val);
			return;
		};
	};
	append(bucket, (key, val))!;
};

// Unsets a value in a [[hashmap]] associated with a given key, returning the
// value that was previously stored for that key (or void).
fn unset(map: *hashmap, key: str) (str | void) = {
	const hash = fnv::string(key);
	let bucket = &map[hash % len(map)];
	for (let i = 0z; i < len(bucket); i += 1) {
		const (k, v) = bucket[i];
		if (k == key) {
			delete(bucket[i]);
			return v;
		};
	};
};

// Frees resources associated with a [[hashmap]].
fn finish(map: *hashmap) void = {
	for (let bucket .. map) {
		free(bucket);
	};
};

fn new_hashmap() hashmap = {
	return [[]...];
};

// Demonstrate usage of the hash map
// export fn main() void = {
// 	let map: hashmap = [[]...];
// 	defer finish(&map);

// 	set(&map, "hello", "world");
// 	set(&map, "foo", "bar");

// 	assert(get(&map, "hello") as str == "world");
// 	assert(get(&map, "foo") as str == "bar");
// 	assert(get(&map, "hi there") is void);

// 	assert(unset(&map, "hello") as str == "world");
// 	assert(get(&map, "hello") is void);

// 	// Enumerate keys/values
// 	for (let bucket .. map) {
// 		for (let (key, val) .. bucket) {
// 			fmt::printfln("{}: {}", key, val)!;
// 		};
// 	};
// };


fn display_hashmap(map: hashmap) void = {
	for (let bucket .. map) {
		for (let (key, val) .. bucket) {
			fmt::printfln("{}: {}", key, val)!;
		};
	};
};

