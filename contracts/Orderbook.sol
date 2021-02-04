pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {VariancePosition} from "./VariancePosition.sol";


contract Orderbook is Ownable{
    using SafeMath for uint256;

    mapping(address => VariancePosition.Position[]) public positions;

    uint256[] public orderVaultIds;

    address[] public orderSellers;

    uint256 public contractEpoch;

    constructor(uint256 epoch) {
        contractEpoch = epoch;
    }

    function getPosition(address owner, uint256 index) external view returns(uint256) {
        VariancePosition.Position memory currPosition = positions[owner][index];
        return(currPosition.strike);
    }

    function sellOrder(address owner, uint256 strike, uint256 askPrice, uint256 collateral) onlyOwner external {
        uint256 index;

        index = VariancePosition.findPositionIndex(positions[owner], strike, askPrice);
        VariancePosition.addToPosition(positions[owner], strike, collateral, 0, askPrice, index);
        _addToOrderbook(owner, strike, askPrice, index);
    }

    function _addToOrderbook(address owner, uint256 strike, uint256 askPrice, uint256 vaultId) internal {
        uint256 i;
        uint256 currStrike;
        uint256 currAskPrice;
        uint256 currId;
        address currAddr;
        VariancePosition.Position memory currPosition;

        for(i = 0; i < orderVaultIds.length; i++) {
            currAddr = orderSellers[i];
            currId = orderVaultIds[i];
            currPosition = positions[currAddr][currId];
            currStrike = currPosition.strike;
            currAskPrice = currPosition.askPrice;
            if(strike == currStrike && currAddr == owner && currAskPrice == askPrice) {
                break;
            } else if(strike < currStrike || (strike == currStrike && askPrice < currAskPrice)) {
                _addNewOrder(owner, vaultId, i);
                break;
            } else if(i == orderVaultIds.length - 1) {
                orderVaultIds.push(vaultId);
                orderSellers.push(owner);
                break;
            }
        }
    }

    function _addNewOrder(address addr, uint256 vaultId, uint256 index) internal {
        uint256 i;
        uint256 currId;
        address currAddr;
        uint256 prevId;
        address prevAddr;

        orderVaultIds.push(0);
        orderSellers.push(address(0));
        currId = vaultId;
        currAddr = addr;
        for(i = index; index < orderSellers.length; i++) {
            prevId = orderVaultIds[i];
            prevAddr = orderSellers[i];
            orderVaultIds[i] = currId;
            orderSellers[i] = currAddr;
            currId = prevId;
            currAddr = prevAddr;
        }
    }
}