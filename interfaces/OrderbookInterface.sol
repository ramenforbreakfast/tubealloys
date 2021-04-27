pragma solidity ^0.7.3;

interface OrderbookInterface {
    struct Order {
        address seller;
        uint256 totalUnits;
        uint256 totalAsk;
        uint256 posIdx;
        bool unfilled;
    }

    function getPageSize() external pure returns (uint64);

    function getOrderbookInfo()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            address
        );

    function getOrder(uint256 orderID)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
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
            uint256,
            uint256
        );

    function getOrderPayments(address owner) external view returns (uint256);

    function getUserSettlement(address owner) external view returns (uint256);

    function getNumberOfActiveAddresses() external view returns (uint256);

    function getAddrByIdx(uint256 index) external view returns (address);

    function redeemOrderPayments(address owner) external returns (uint256);

    function redeemUserSettlement(address owner) external returns (uint256);

    function isSettled() external view returns (bool);

    function sellOrder(
        address seller,
        uint256 strike,
        uint256 totalAsk,
        uint256 totalUnits
    ) external returns (uint256);

    function fillBuyOrderByMaxPrice(
        address buyer,
        uint256 minStrike,
        uint256 amountToSpend
    ) external returns (uint256);

    function getBuyOrderByUnitAmount(uint256 minStrike, uint256 unitsRequested)
        external
        view
        returns (
            uint256,
            uint256,
            uint256[1000] memory
        );

    function settleOrderbook(uint256 realizedVar) external;
}
