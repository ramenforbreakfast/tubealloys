pragma solidity ^0.7.3;

interface OrderbookInterface {
    struct Order {
        uint256 askPrice;
        uint256 posIdx;
        address seller;
        bool unfilled;
    }

    function getPageSize() external pure returns (uint64);

    function getOrderbookInfo()
        external
        view
        returns (
            uint256,
            uint256,
            address,
            uint256
        );

    function getNumberOfOrders() external view returns (uint256);

    function getOrder(uint256 index)
        external
        view
        returns (
            uint256,
            uint256,
            address
        );

    function getNumberOfUserPositions(address addr)
        external
        view
        returns (uint256);

    function getPosition(address owner, uint256 index)
        external
        view
        returns (
            uint256,
            int128,
            int128
        );

    function getFilledOrderPayment(address owner)
        external
        view
        returns (uint256);

    function getUserSettlement(address owner) external view returns (uint256);

    function getNumberOfActiveAddresses() external view returns (uint256);

    function getAddrByIdx(uint256 index) external view returns (address);

    function redeemFilledOrderPayment(address owner) external returns (uint256);

    function redeemUserSettlement(address owner) external returns (uint256);

    function isSettled() external view returns (bool);

    function setUserSettlement(address owner, uint256 settlement) external;

    function sellOrder(
        address seller,
        uint256 strike,
        uint256 askPrice,
        int128 positionSize
    ) external;

    function fillBuyOrderByMaxPrice(
        address buyer,
        uint256 minStrike,
        uint256 maxPrice
    ) external returns (uint256);

    function getBuyOrderByUnitAmount(uint256 minStrike, int128 uintAmount)
        external
        view
        returns (
            uint256,
            int128,
            int128[1000] memory,
            uint256[1000] memory
        );

    function settleOrderbook(uint256 realizedVar) external;
}
