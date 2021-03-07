pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract Pool is Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getUserBalance(address user) external view returns (uint256) {
        return _balances[user];
    }

    function deposit() external payable {
        _balances[msg.sender] = _balances[msg.sender].add(msg.value);
    }

    function withdraw(uint256 amount) external {
        require(
            _balances[msg.sender] >= amount,
            "Pool: insufficient funds for withdrawal!"
        );

        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        msg.sender.transfer(amount);
    }

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(
            _balances[from] >= amount,
            "Pool: insufficient funds for transfer!"
        );
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount);
    }
}
