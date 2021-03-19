pragma solidity ^0.7.3;

interface PoolInterface {
    function getContractBalance(uint256 roundStart, uint256 roundEnd)
        external
        view
        returns (uint256);

    function getUserBalance(address user) external view returns (uint256);

    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external;
}
