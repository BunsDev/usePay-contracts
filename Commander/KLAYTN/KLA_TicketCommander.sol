// SPDX-License-Identifier: GNU LGPLv3
pragma solidity >=0.8.0;

import "../../Pack/TicketPack.sol";
import "./KLA_Commander.sol";

contract KLA_TicketCommander is Ticket, KLA_Commander {
    event buyEvent(address indexed pack, uint256 buyNum, address buyer, uint256 count); // 0: pack indexed, 1: buyer, 2: count
    event useEvent(address indexed pack, address user, uint256 count); // 0: pack indexed, 1: buyer, 2: count
    event requestRefundEvent(address indexed pack, address buyer, uint256 count, uint256 money); // 0: pack indexed, 1: buyer, 2: count
    event calculateEvent(address indexed, address owner, uint256 value);
    event changeTotalEvent(address indexed, uint256 _before, uint256 _after);

    modifier onlyOwner() {
        require(msg.sender == owner, "O01 - Only for issuer");
        _;
    }

    modifier onCalculateTime() {
        require(block.timestamp > packInfo.times3, "CT01 - Not available time for calculate");
        _;
    }

    modifier canUse(uint256 count) {
        require(
            buyList[msg.sender].hasCount - buyList[msg.sender].useCount >= count,
            "U02 - Not enough owned count"
        );
        _;
    }

    modifier canBuy(uint256 count) {
        require(
            block.timestamp >= packInfo.times0 && block.timestamp <= packInfo.times1,
            "B01 - Not available time for buy"
        );
        require(quantity - count >= 0, "B04 - Not enough quentity");
        require(count <= packInfo.maxCount, "B05 - Exceeding the available quantity");
        _;
    }

    function buy(uint32 count, uint256 buyNum) external payable canBuy(count) {
        if (packInfo.tokenType == 100) {
            require(msg.value == packInfo.price * (count), "B03 - Not enough value");
        } else {
            (bool success, ) = getAddress(packInfo.tokenType).call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender,
                    address(this),
                    packInfo.price * (count)
                )
            );

            require(success, "T01 - Token transfer failed");
        }

        _buy(count, msg.sender);

        emit buyEvent(address(this), buyNum, msg.sender, count);
    }

    function give(address[] memory toAddr) external canUse(toAddr.length) {
        buyList[msg.sender].hasCount = buyList[msg.sender].hasCount - uint32(toAddr.length);

        for (uint i = 0; i < toAddr.length; i++) {
            buyList[toAddr[i]].hasCount++;
        }

        emit giveEvent(address(this), msg.sender, toAddr);
    }

    function use(uint32 _count) external canUse(_count) {
        require(block.timestamp > packInfo.times2, "U01 - Not available time for use");

        totalUsedCount = totalUsedCount + _count;
        buyList[msg.sender].useCount = buyList[msg.sender].useCount + (_count);

        _transfer(packInfo.tokenType, owner, packInfo.price * (_count));

        emit useEvent(address(this), msg.sender, _count);
    }

    function requestRefund(uint32 _count)
        external
        canUse(_count)
        blockReEntry
        haltInEmergency
        requestLimit(1 minutes)
    {
        uint256 refundValue = 0;
        buyList[msg.sender].hasCount = buyList[msg.sender].hasCount - _count;

        if (block.timestamp < packInfo.times1) {
            quantity = quantity + _count;
        }

        if (block.timestamp > packInfo.times2 && block.timestamp < packInfo.times3) {
            // in useTime
            totalUsedCount = totalUsedCount + _count;
            (refundValue) = _refund(msg.sender, packInfo.price * _count);
        } else if (block.timestamp > packInfo.times3) {
            // out useTime
            uint totalValue = packInfo.price * _count;
            uint value = _percentValue(totalValue, 100 - packInfo.noshowValue);
            (refundValue) = _refund(msg.sender, value);
        }

        emit requestRefundEvent(address(this), msg.sender, _count, refundValue);
    }

    function calculate() external onlyOwner onCalculateTime {
        require(isCalculated == 0, "CT03 - Already calculated pack");

        uint quantityCount = packInfo.total - quantity - totalUsedCount;
        uint qunaityValue = _percentValue(packInfo.price, packInfo.noshowValue) * quantityCount;

        isCalculated = 1;
        _transfer(packInfo.tokenType, owner, qunaityValue);

        emit calculateEvent(address(this), owner, qunaityValue);
    }

    function changeTotal(uint32 count) external payable onlyOwner {
        require(packInfo.total - quantity <= count, "TC01 - Less than the remaining quantity");
        require(count <= 1000, "C05 - Limit count over");

        if (count > packInfo.total) {
            checkFee(count - packInfo.total);
            _transfer(100, getAddress(0), msg.value);
        }

        quantity = quantity - (packInfo.total - count);
        packInfo.total = count;

        emit changeTotalEvent(address(this), packInfo.total, count);
    }

    function viewInfo() external view returns (PackInfo memory) {
        return packInfo;
    }

    function viewUser(address _addr) external view returns (pack memory) {
        return buyList[_addr];
    }

    function viewQuantity() external view returns (uint256) {
        return quantity;
    }

    function viewOwner() external view returns (address) {
        return owner;
    }

    function viewVersion() external view returns (uint8) {
        return ver;
    }

    function viewTotalUsedCount() external view returns (uint32) {
        return totalUsedCount;
    }

    function _percentValue(uint value, uint8 percent) private view returns (uint) {
        (bool success, bytes memory resultPercentValue) = getAddress(1300).staticcall(
            abi.encodeWithSignature("getPercentValue(uint256,uint256)", value, percent)
        );

        require(success, "Getting a value of the percent is failed");

        return abi.decode(resultPercentValue, (uint));
    }

    function _buy(uint32 count, address buyer) private {
        buyList[buyer].hasCount = buyList[buyer].hasCount + (count);
        quantity = quantity - count;
    }

    function _refund(address _to, uint value) private returns (uint256) {
        uint refundValue = value;

        _transfer(packInfo.tokenType, _to, refundValue);

        return refundValue;
    }
}
