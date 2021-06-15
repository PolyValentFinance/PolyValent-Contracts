// Socials


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/BEP20.sol";

contract Electron is  BEP20("Electron","ELECTRON",18){
    
    uint16 public _maxTxPercentageBP; //400 -> 4%
    mapping (address=>bool) isExcluded;

    constructor(uint16 maxTx){
        require(maxTx>=50 && maxTx<=10000, "Electron: constructor: maxTx Percentage should be between [0.5-100]%"); // always max transaction amount % should be between 0.5 and 100 to dont stop trading.
        _maxTxPercentageBP = maxTx;
    }

    function mint(address recipient, uint256 amount) public onlyOwner{
        _mint(recipient, amount);
    }

    function retrieveErrorTokens(IBEP20 token_, address to_) public onlyOwner{
        token_.transfer(to_, token_.balanceOf(address(this)));
    }

    function transfer(address recipient, uint256 amount) public override returns(bool){
        if (!isExcluded[_msgSender()] && !isExcluded[recipient] ){
            require(amount<=(totalSupply()*_maxTxPercentageBP)/10000,"Electron: Transfer: transfering over Max Transaction");
        }
        return super.transfer(recipient, amount);
    }

    function setMaxTxPercentage(uint16 newPercentage)public onlyOwner{
        require(newPercentage>=50 && newPercentage<=10000, "Electron: setMaxTxPercentage: New Percentage should be between [0.5-100]%"); // always max transaction amount % should be between 0.5 and 100 to dont stop trading.
        _maxTxPercentageBP = newPercentage;
    }

    function setExcludeMaxTransactionAddress(address exclude, bool state) public onlyOwner{
        isExcluded[exclude] = state;
    }


}