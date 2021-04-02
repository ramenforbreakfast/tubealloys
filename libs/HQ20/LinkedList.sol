pragma solidity ^0.6.0;

/**
 * @title LinkedList
 * @dev Data structure
 * @author Alberto Cuesta Cañada
 */
library LinkedList {
    event ObjectCreated(uint256 id, bytes32 data);
    event ObjectsLinked(uint256 prev, uint256 next);
    event ObjectRemoved(uint256 id);
    event NewHead(uint256 id);

    struct Object {
        uint256 id;
        uint256 next;
        bytes32 data;
    }

    struct List {
        bool initialized;
        uint256 head;
        uint256 idCounter;
        mapping(uint256 => Object) objects;
    }

    /**
     * @dev Creates an empty list.
     */
    function newList(List storage self) internal {
        self.initialized = true;
        self.head = 0;
        self.idCounter = 1;
    }

    /**
     * @dev Retrieves the Object denoted by `_id`.
     */
    function get(List storage self, uint256 _id)
        internal
        view
        returns (
            uint256,
            uint256,
            bytes32
        )
    {
        Object memory object = self.objects[_id];
        return (object.id, object.next, object.data);
    }

    /**
     * @dev Given an Object, denoted by `_id`, returns the id of the Object that points to it, or 0 if `_id` refers to the Head.
     */
    function findPrevId(List storage self, uint256 _id)
        internal
        view
        returns (uint256)
    {
        if (_id == self.head) return 0;
        Object memory prevObject = self.objects[self.head];
        while (prevObject.next != _id) {
            prevObject = self.objects[prevObject.next];
        }
        return prevObject.id;
    }

    /**
     * @dev Returns the id for the Tail.
     */
    function findTailId(List storage self) internal view returns (uint256) {
        Object memory oldTailObject = self.objects[self.head];
        while (oldTailObject.next != 0) {
            oldTailObject = self.objects[oldTailObject.next];
        }
        return oldTailObject.id;
    }

    /**
     * @dev Return the id of the first Object matching `_data` in the data field.
     */
    function findIdForData(List storage self, bytes32 _data)
        internal
        view
        returns (uint256)
    {
        Object memory object = self.objects[self.head];
        while (object.data != _data) {
            object = self.objects[object.next];
        }
        return object.id;
    }

    /**
     * @dev Insert a new Object as the new Head with `_data` in the data field.
     */
    function addHead(List storage self, bytes32 _data) internal {
        if (self.initialized != true) {
            newList(self);
        }
        uint256 objectId = _createObject(_data);
        _link(objectId, self.head);
        _setHead(objectId);
    }

    /**
     * @dev Insert a new Object as the new Tail with `_data` in the data field.
     */
    function addTail(List storage self, bytes32 _data) internal {
        if (self.initialized != true) {
            newList(self);
        }
        if (self.head == 0) {
            addHead(_data);
        } else {
            uint256 oldTailId = findTailId();
            uint256 newTailId = _createObject(_data);
            _link(oldTailId, newTailId);
        }
    }

    /**
     * @dev Remove the Object denoted by `_id` from the List.
     */
    function remove(List storage self, uint256 _id) internal {
        if (self.initialized != true) {
            newList(self);
        }
        Object memory removeObject = self.objects[_id];
        if (self.head == _id) {
            _setHead(removeObject.next);
        } else {
            uint256 prevObjectId = findPrevId(_id);
            _link(prevObjectId, removeObject.next);
        }
        delete self.objects[removeObject.id];
        emit ObjectRemoved(_id);
    }

    /**
     * @dev Insert a new Object after the Object denoted by `_id` with `_data` in the data field.
     */
    function insertAfter(
        List storage self,
        uint256 _prevId,
        bytes32 _data
    ) internal {
        if (self.initialized != true) {
            newList(self);
        }
        Object memory prevObject = self.objects[_prevId];
        uint256 newObjectId = _createObject(_data);
        _link(newObjectId, prevObject.next);
        _link(prevObject.id, newObjectId);
    }

    /**
     * @dev Insert a new Object before the Object denoted by `_id` with `_data` in the data field.
     */
    function insertBefore(
        List storage self,
        uint256 _nextId,
        bytes32 _data
    ) internal {
        if (self.initialized != true) {
            newList(self);
        }
        if (_nextId == self.head) {
            addHead(_data);
        } else {
            uint256 prevId = findPrevId(_nextId);
            insertAfter(prevId, _data);
        }
    }

    /**
     * @dev Internal function to update the Head pointer.
     */
    function _setHead(List storage self, uint256 _id) internal {
        if (self.initialized != true) {
            newList(self);
        }
        self.head = _id;
        emit NewHead(_id);
    }

    /**
     * @dev Internal function to create an unlinked Object.
     */
    function _createObject(List storage self, bytes32 _data)
        internal
        returns (uint256)
    {
        if (self.initialized != true) {
            newList(self);
        }
        uint256 newId = self.idCounter;
        self.idCounter += 1;
        Object memory object = Object(newId, 0, _data);
        self.objects[object.id] = object;
        emit ObjectCreated(object.id, object.data);
        return object.id;
    }

    /**
     * @dev Internal function to link an Object to another.
     */
    function _link(
        List storage self,
        uint256 _prevId,
        uint256 _nextId
    ) internal {
        if (self.initialized != true) {
            newList(self);
        }
        self.objects[_prevId].next = _nextId;
        emit ObjectsLinked(_prevId, _nextId);
    }
}
