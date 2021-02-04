pragma solidity ^0.7.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {VariancePosition} from "./VariancePosition.sol";


contract Orderbook is Ownable{
    using SafeMath for uint256;

    struct Order {
        uint256 askPrice;
        uint256 vaultId;
        address sellerAddress;
    }

    mapping(address => VariancePosition.Position[]) public positions;

    Order[] public openOrders;

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

        index = VariancePosition.findPositionIndex(positions[owner], strike);
        VariancePosition.addToPosition(positions[owner], strike, collateral, 0, index);
        _addToOrderbook(owner, strike, askPrice, index);
    }

    function _addToOrderbook(address owner, uint256 strike, uint256 askPrice, uint256 vaultId) internal {
        uint256 i;
        uint256 currStrike;
        uint256 currAskPrice;
        uint256 currId;
        address currAddr;
        uint256 orderSize = openOrders.length;

        for(i = 0; i < orderSize; i++) {
            currAddr = openOrders[i].sellerAddress;
            currId = openOrders[i].vaultId;
            currAskPrice = openOrders[i].askPrice;
            currStrike = positions[currAddr][currId].strike;
            if(strike == currStrike && currAddr == owner && currAskPrice == askPrice) {
                break;
            } else if(strike < currStrike || (strike == currStrike && askPrice < currAskPrice)) {
                _addNewOrder(owner, askPrice, vaultId, i);
                break;
            } else if(i == orderSize - 1) {
                openOrders.push(Order(askPrice, vaultId, owner));
                break;
            }
        }
    }

    function _addNewOrder(address addr, uint256 askPrice, uint256 vaultId, uint256 index) internal {
        uint256 i;
        uint256 currId;
        uint256 currAskPrice;
        address currAddr;
        uint256 prevId;
        uint256 prevAskPrice;
        address prevAddr;

        openOrders.push(Order(0, 0, address(0)));
        currId = vaultId;
        currAddr = addr;
        currAskPrice = askPrice;
        for(i = index; index < openOrders.length; i++) {
            prevAskPrice = openOrders[i].askPrice;
            prevId = openOrders[i].vaultId;
            prevAddr = openOrders[i].sellerAddress;
            openOrders[i].askPrice = currAskPrice;
            openOrders[i].vaultId = currId;
            openOrders[i].sellerAddress = currAddr;
            currId = prevId;
            currAddr = prevAddr;
            currAskPrice = prevAskPrice;
        }
    }
}