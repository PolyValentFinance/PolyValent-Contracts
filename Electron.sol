// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/BEP20.sol";

contract Electron is  BEP20("Electron","E-",18){
    
    uint256 private immutable _maxSupply;  

    constructor(uint256 maxSupply_){
        //_mint(owner(), maxSupply_/100);
        _maxSupply = maxSupply_;
    }

    function mint(address recipient, uint256 amount) public onlyOwner{
        if (totalSupply() == maxSupply()) return;
        if (totalSupply()+amount > maxSupply()){
            _mint(recipient, maxSupply()-totalSupply());
        }else{
            _mint(recipient, amount);
        }
    }

    function maxSupply() public view returns(uint256){
        return _maxSupply;
    }

    function retrieveErrorTokens(IBEP20 token_, address to_) public onlyOwner{
        token_.transfer(to_, token_.balanceOf(address(this)));
    }


}