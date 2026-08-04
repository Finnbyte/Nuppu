use fmt;

export type LinkedListNode = struct {
	value: *opaque,
	next: nullable *LinkedListNode
};

export type LinkedList = struct {
	head: nullable *LinkedListNode
};

export fn ll_len(tree: *LinkedList) size = {
	if (tree.head == null) return 0;
	let node: *LinkedListNode = tree.head as *LinkedListNode;
	let i = 1z;
	for (node.next != null) {
		node = node.next as *LinkedListNode;
		i += 1;
	};

	return i;
};

export fn ll_value(node: nullable *LinkedListNode) nullable *opaque = {
	return match (node) {
	case let node: *LinkedListNode => yield node.value: *opaque;
	case null => yield null;
	};
};

export fn ll_empty(tree: *LinkedList) bool = {
	return tree.head == null;
};

// export fn ll_iterator(node: *LinkedListNode) bool = {
// 	if (node.next is null) return false;
// };

// export fn ll_next(node: *LinkedListNode) bool = {
// 	if (node.next is null) return false;
// };

export fn ll_secondlast(tree: *LinkedList) nullable *LinkedListNode = {
	if (tree.head == null) {
		return null;
	};
	let node: *LinkedListNode = tree.head as *LinkedListNode;
	for (node.next != null) node = node.next as *LinkedListNode;
	return node;
};

export fn ll_head(tree: *LinkedList) *LinkedListNode = {
	return tree.head: *LinkedListNode;
};

export fn ll_first(tree: *LinkedList) nullable *LinkedListNode = {
	return tree.head;
};

export fn ll_last(tree: *LinkedList) nullable *LinkedListNode = {
	if (tree.head == null) {
		return null;
	};
	let node: *LinkedListNode = tree.head as *LinkedListNode;
	for (!(node.next is null)) node = node.next as *LinkedListNode;
	return node;
};

export fn ll_nth(tree: *LinkedList, index: int) nullable *LinkedListNode = {
	if (index <= 0) return tree.head;
	if (tree.head == null) {
		return null;
	};
	let i = 0;
	let node: *LinkedListNode = tree.head as *LinkedListNode;
	for (node.next != null) {
		if (i == index) return node;
		node = node.next as *LinkedListNode;
		i += 1;
	};
	return null;
};

export fn ll_show(tree: *LinkedList) void = {
	if (tree.head == null) {
		fmt::println("Zero-length tree")!;
	} else {
		let node = tree.head;
		let i = 0;
		for (node != null) {
			fmt::printfln("Node: {}, Address: {}", i, node)!;
			node = (node as *LinkedListNode).next;
			i += 1;
		};
	};
};

export fn ll_push(tree: *LinkedList, value: *opaque) void = {
	const new_node = alloc(LinkedListNode {
		value = value,
		next = null
	})!;
	const node = ll_last(tree);
	match (node) {
	case let node: *LinkedListNode => node.next = new_node;
	case null => tree.head = new_node;
	};
};


export fn ll_remove(tree: *LinkedList, index: int) void = {
	match (ll_nth(tree, index - 1)) {
	case let node: *LinkedListNode =>
		const node_to_delete = node.next;
		fmt::println("node", node)!;
		if (node_to_delete != null) {
			node.next = (node_to_delete as *LinkedListNode).next;
		};
	case null => return;
	};
};

