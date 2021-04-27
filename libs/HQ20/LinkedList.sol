pragma solidity ^0.7.3;

/**
 * @title LinkedList
 * @dev Data structure
 * @author Alberto Cuesta Cañada
 */
library LinkedList {
    struct Object {
        uint256 id;
        uint256 next;
        uint256 data;
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
            uint256
        )
    {
        require(self.initialized == true, "List has not been initialized!");
        return (
            self.objects[_id].id,
            self.objects[_id].next,
            self.objects[_id].data
        );
    }

    /**
     * @dev Given an Object, denoted by `_id`, returns the id of the Object that points to it, or 0 if `_id` refers to the Head.
     */
    function findPrevId(List storage self, uint256 _id)
        internal
        view
        returns (uint256)
    {
        require(self.initialized == true, "List has not been initialized!");
        if (_id == self.head) return 0;
        uint256 prevNext = self.objects[self.head].next;
        while (prevNext != _id) {
            prevNext = self.objects[prevNext].next;
        }
        return self.objects[prevNext].id;
    }

    /**
     * @dev Returns the id for the Tail.
     */
    function findTailId(List storage self) internal view returns (uint256) {
        require(self.initialized == true, "List has not been initialized!");
        uint256 prevNext = self.objects[self.head].next;
        while (prevNext != 0) {
            prevNext = self.objects[prevNext].next;
        }
        return self.objects[prevNext].id;
    }

    /**
     * @dev Return the id of the first Object matching `_data` in the data field.
     */
    function findIdForData(List storage self, uint256 _data)
        internal
        view
        returns (uint256)
    {
        require(self.initialized == true, "List has not been initialized!");
        uint256 prevObjNext = self.head;
        while (self.objects[prevObjNext].data != _data) {
            prevObjNext = self.objects[prevObjNext].next;
        }
        return self.objects[prevObjNext].id;
    }

    /**
     * @dev Insert a new Object as the new Head with `_data` in the data field.
     */
    function addHead(List storage self, uint256 _data) internal {
        if (self.initialized != true) {
            newList(self);
        }
        uint256 objectId = _createObject(self, _data);
        _link(self, objectId, self.head);
        _setHead(self, objectId);
    }

    /**
     * @dev Insert a new Object as the new Tail with `_data` in the data field.
     */
    function addTail(List storage self, uint256 _data) internal {
        if (self.initialized != true) {
            newList(self);
        }
        if (self.head == 0) {
            addHead(self, _data);
        } else {
            uint256 oldTailId = findTailId(self);
            uint256 newTailId = _createObject(self, _data);
            _link(self, oldTailId, newTailId);
        }
    }

    /**
     * @dev Remove the Object denoted by `_id` from the List.
     */
    function remove(List storage self, uint256 _id) internal {
        if (self.initialized != true) {
            newList(self);
        }
        if (self.head == _id) {
            _setHead(self, self.objects[_id].next);
        } else {
            uint256 prevObjectId = findPrevId(self, _id);
            _link(self, prevObjectId, self.objects[_id].next);
        }
        delete self.objects[_id];
    }

    /**
     * @dev Insert a new Object after the Object denoted by `_id` with `_data` in the data field.
     */
    function insertAfter(
        List storage self,
        uint256 _prevId,
        uint256 _data
    ) internal {
        if (self.initialized != true) {
            newList(self);
        }
        uint256 newObjectId = _createObject(self, _data);
        _link(self, newObjectId, self.objects[_prevId].next);
        _link(self, _prevId, newObjectId);
    }

    /**
     * @dev Insert a new Object before the Object denoted by `_id` with `_data` in the data field.
     */
    function insertBefore(
        List storage self,
        uint256 _nextId,
        uint256 _data
    ) internal {
        if (self.initialized != true) {
            newList(self);
        }
        if (_nextId == self.head) {
            addHead(self, _data);
        } else {
            uint256 prevId = findPrevId(self, _nextId);
            insertAfter(self, prevId, _data);
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
    }

    /**
     * @dev Internal function to create an unlinked Object.
     */
    function _createObject(List storage self, uint256 _data)
        internal
        returns (uint256)
    {
        if (self.initialized != true) {
            newList(self);
        }
        uint256 newId = self.idCounter;
        self.idCounter += 1;
        self.objects[newId] = Object(newId, 0, _data);
        return newId;
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
    }
}
