// SPDX-License-Identifier: MIT

pragma solidity>=0.8.0;

import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IERC721.sol";

contract NFTSwap is IERC721Receiver {
    // Variables
    // NFTs that allowed to be exchanged by this contract
    mapping (address => bool) private _allowed_to_exchange;
    
    // contract allowed operators
    mapping (address => bool) private _privilleged_operators;
    // contract owner
    address public owner;
    
    // Interface to halt all auctions.
    bool public IsHalted;
    
    // Account Balance
    mapping (address => uint256) public balance;

    // NFTs ownership information
    mapping (address => mapping (uint256 => address)) private _ownership; 
    
    // NFTs auctions status
    mapping (address => mapping (uint256 => bool)) public onAuction;
    mapping (address => mapping (uint256 => uint256)) public current_auction_price;
    mapping (address => mapping (uint256 => address)) public current_bidder;
    mapping (address => mapping (uint256 => uint256)) public bid_end_time;
    
    // Events
    // Change Operators
    event OperatorCh(address operator, bool chType);
    // Ownership transfer
    event Owner(address newOwner);
    // Admin withdrawal
    event AdminWithDrawal(uint256 amount);
    // Pause and resume
    event Pause();
    event Resume();
    // New Bidding Event
    event NewBid(address NFTContract, uint256 NFTId, uint256 price, address bidder);
    // Auction Finish Event
    event AuctionMade(address NFTContract, uint256 NFTId, address bidder);
    // Force bid removal event
    event ForceRemoval(address Operator, address NFTContract, uint256 NFTId, address bidder);
    
    // Management interfaces:
    // constructor
    constructor() {
        owner = msg.sender;
        _privilleged_operators[msg.sender] = true;
    }
    
    // Add _privilleged_operators
    function addOperator(address operator) public {
        require(msg.sender == owner, "Only contract creator is allowed to do this.");
        _privilleged_operators[operator] = true;
        emit OperatorCh(operator, true);
    }
    
    // Remove someone from operators
    function removeOperator(address operator) public {
        require(msg.sender == owner, "Only contract creator is allowed to do this.");
        _privilleged_operators[operator] = false;
        emit OperatorCh(operator, false);
    }
    
    // Transfer contract ownership, please be extremly careful while using this
    function transferOwnership(address newOwner) public {
        require(msg.sender == owner, "Only contract creator is allowed to do this.");
        owner = newOwner;
        emit Owner(newOwner);
    }
    
    // Halt transactions
    function halt() public {
        require(_privilleged_operators[msg.sender] == true, "Operator only");
        IsHalted = true;
        emit Pause();
    }
    
    // Resume transactions
    function resume() public {
        require(_privilleged_operators[msg.sender] == true, "Operator only");
        IsHalted = false;
        emit Resume();
    }
    
    // Force cancel bid, to prevent DDoS by bidding from contract.
    function force_remove_bid(address NFTContract, uint256 NFTId) public {
        require(_privilleged_operators[msg.sender] == true, "Operator only");
        // Remove bid and disable the nft's auction.
        onAuction[NFTContract][NFTId] == false;
        bid_end_time[NFTContract][NFTId] == 2**256 - 1;
        balance[current_bidder[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        emit ForceRemoval(msg.sender, NFTContract, NFTId, current_bidder[NFTContract][NFTId]);
    }

    // Allow to auction specified token
    function allow(address NFTContract) public {
        require(_privilleged_operators[msg.sender], "Denied");
        _allowed_to_exchange[NFTContract] = true;
    }

    function disallow(address NFTContract) public {
        require(_privilleged_operators[msg.sender], "Denied");
        _allowed_to_exchange[NFTContract] = false;
    }
    
    // Withdrawal methods
    function withDrawEther(uint256 amount) public {
        require(balance[msg.sender] >= amount, "Balance not sufficient.");
        balance[msg.sender] -= amount;
        address payable out = payable(msg.sender);
        out.transfer(amount);
    }

    function withDrawERC721(address NFTContract, uint256 NFTId) public payable {
        require(onAuction[NFTContract][NFTId] == false, "The nft is still on auction, pls claim it or wait for finish");
        require(_ownership[NFTContract][NFTId] == msg.sender, "You must be the token's owner");
        _ownership[NFTContract][NFTId] = address(0);
        ERC721(NFTContract).safeTransferFrom(address(this), msg.sender, NFTId);
        // Currently we do not support using approval mechinesm or paid transfer. This will be added later
    }

    function ownerWithdrawal(uint256 amount) public {
        require(msg.sender == owner);
        payable(msg.sender).transfer(amount);
        emit AdminWithDrawal(amount);
    }

    // Auction Ops

    function startAuction(address NFTContract, uint256 NFTId, uint256 lowest_price) public {
        require(msg.sender == _ownership[NFTContract][NFTId], "Permission denied");
        // 1. Set lowest bid
        current_auction_price[NFTContract][NFTId] = lowest_price;
        current_bidder[NFTContract][NFTId] = msg.sender;
        // 2. Enable Auction
        onAuction[NFTContract][NFTId] = true;
        // 3. Set timestamp
        bid_end_time[NFTContract][NFTId] = block.number + 5760;
    }

    function bid(address NFTContract, uint256 NFTId) public payable {
        require(msg.value > current_auction_price[NFTContract][NFTId], "Must bid higher");
        require(onAuction[NFTContract][NFTId], "Not for Auction");
        // 0. Refund previous guy
        balance[current_bidder[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        // 1. Change price
        current_auction_price[NFTContract][NFTId] = msg.value;
        // 2. Change bidder
        current_bidder[NFTContract][NFTId] = msg.sender;
        // 3. Set timestamp
        bid_end_time[NFTContract][NFTId] = block.number + 5760;
    }

    function claimAuction(address NFTContract, uint256 NFTId) public {
        require(block.number > bid_end_time[NFTContract][NFTId], "Auction still active.");
        require(msg.sender == _ownership[NFTContract][NFTId] 
        || msg.sender == current_bidder[NFTContract][NFTId],
         "You are not allowed to do this.");
        // 1. Disable the auction
        onAuction[NFTContract][NFTId] = false;
        // 2. Transfer the value
        balance[_ownership[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        // 3. Transfer the ownership
        _ownership[NFTContract][NFTId] = current_bidder[NFTContract][NFTId];
        emit AuctionMade(NFTContract, NFTId, current_bidder[NFTContract][NFTId]);
    }
    
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        // Check if the contract is approved for receiving
        require(_allowed_to_exchange[msg.sender], "Token not approved for auction");
        // Set token ownership
        _ownership[msg.sender][tokenId] = from;
        return bytes4(this.onERC721Received.selector);
    }
}