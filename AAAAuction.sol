// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";

contract AAAAuction is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    // Member Details
    struct Member {
        string name;
        address uaddress;
        string imageUrl;
    }

    // States of an item
    enum State {
        Bidding,
        ToPurchase,
        Default
    }

    // Item data
     struct Item {
        // string name;
        // string description;
        // address owner;
        // string imageUrl;
        address owner;
        uint256 itemId;
        uint256 reserve; // check initialization
        uint256 highestItemBidValue;
        uint256 currentPrice;
        int bidStartTime;
        // uint256 x;
        // members owner;
    }

    struct ItemWrapper {
        Item item;
        State state;
    }

    Item[] public allItems;
    // mapping of an Item with tokenId
    
    mapping(uint256 => Item) public itemPerId;
    
    // store total tokens count
    uint public tokenCount;
    int timeToBidInSeconds;
    uint8 discountAmount;
    // uint8 markupPercentage;
    // store members who bid on item
    mapping(uint256 => mapping(address => bool)) bidPerItem;
    // fetch owner details based on address
    mapping(address => Member) public memberInfo;
    // store total members count
    uint public memberCount;
    // Auction Fees
    uint auctionFeePercent;
    // Auctioneer
    address payable auctioneer;
    constructor(int _timeToBidInSeconds, uint8 _discountAmount, uint8 _auctionFeePercent) ERC721("AAA Auction", "AAA") {
        auctioneer = payable(msg.sender);
        timeToBidInSeconds = _timeToBidInSeconds;
        discountAmount = _discountAmount;
        auctionFeePercent = _auctionFeePercent;
    }

    // function getAllItems() public returns (ItemWrapper[] memory items){
    //     // ItemWrapper[] memory items;
    //     items = new ItemWrapper[](tokenCount);
    //     for(uint8 tokenId=0; tokenId<= tokenCount; tokenId++){
    //         ItemWrapper memory item = ItemWrapper(itemPerId[tokenId], getBidState(tokenId));
    //         items[tokenId] = item;
    //     }
    //     return items;
    // }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721URIStorage) returns (bool) {
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
    }

    function getBidState(uint256 tokenId) public view returns (State){
        Item memory item = itemPerId[tokenId];
        console.log(block.timestamp);
        console.log(uint256(item.bidStartTime+timeToBidInSeconds));
        if(item.bidStartTime <= 0) {
            return State.Default;
        }
        else if(block.timestamp < uint256(item.bidStartTime+timeToBidInSeconds)){
            return State.Bidding;
        }else{
            return State.ToPurchase;
        }
    }

    function safeMint(string memory uri) public {
        address to = msg.sender;
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        Item memory newItem = Item(to, tokenId, 0, 0, 0, 0);
        itemPerId[tokenId] = newItem;
        tokenCount++;
    }
    function addMember(string memory memberName, string memory memberImage) public {
        address memberAddress = msg.sender;
        require(memberAddress != address(0), "Not a valid Address");
        require(memberInfo[memberAddress].uaddress == address(0), "Member already exists");
        memberInfo[memberAddress] = Member(memberName, memberAddress, memberImage);
        memberCount++;
    }
    function bid(uint256 tokenId, uint256 bidValue) public {
        address from = msg.sender;
        require(ERC721.ownerOf(tokenId) != address(0), "No such token exists");
        // require(!bidPerItem[tokenId][from], "Already placed a bid");
        require(getBidState(tokenId) == State.Bidding, "Not available for bidding");
        bidPerItem[tokenId][from] = true;
        if(itemPerId[tokenId].highestItemBidValue < bidValue){
            Item storage curItem = itemPerId[tokenId];
            curItem.highestItemBidValue = bidValue;   
        }
    }

    function getPrice(uint256 tokenId) public view returns(uint256 currentPrice){
        require(getBidState(tokenId) == State.ToPurchase, "Price cannot be disclosed right now");
        console.log(itemPerId[tokenId].highestItemBidValue/100);
        currentPrice =  itemPerId[tokenId].highestItemBidValue + (itemPerId[tokenId].highestItemBidValue/100 * (auctionFeePercent));
        console.log(discountAmount*((block.timestamp - uint256(itemPerId[tokenId].bidStartTime))/120));
        currentPrice = currentPrice - (discountAmount*((block.timestamp - uint256(itemPerId[tokenId].bidStartTime))/120));
        return currentPrice;
    }

    function buy(address to, uint256 tokenId) public payable {
        require(ERC721.ownerOf(tokenId) != address(0), "No such token exists");
        require(bidPerItem[tokenId][to], "Did not bid for the item");

        uint256 currentPrice = getPrice(tokenId);
        require(msg.value >= currentPrice, "Value should be greater than or equal to current token price");
        if(msg.value < itemPerId[tokenId].reserve) {
            Item storage curItemToReset  = itemPerId[tokenId];
            // curItemToReset.state = State.Default;
            curItemToReset.highestItemBidValue = 0;
            curItemToReset.reserve = 0;
            curItemToReset.bidStartTime = 0;
            revert("Owner does not want to sell below a base price");
        }
        uint256 amount = msg.value;
        uint256 auctionFees = amount * auctionFeePercent;
        uint256 amountToOwner = amount - auctionFees;
        address owner = ERC721.ownerOf(tokenId);
        (bool success, ) = owner.call{value: amountToOwner}("");
        require(success, "Payment failed");
        _safeTransfer(to, owner, tokenId, "");
        Item storage curItem  = itemPerId[tokenId];
        curItem.owner = to;
        // curItem.state = State.Default;
        curItem.highestItemBidValue = 0;
        curItem.currentPrice = amount;
        curItem.reserve = 0;
        curItem.bidStartTime = 0;
    }
    function sell(uint tokenId, uint256 basePrice) public {
        address tokenOwner = ERC721.ownerOf(tokenId);
        require(tokenOwner != address(0), "No such token exists");
        require(tokenOwner == msg.sender, "Only owner can sell");
        Item storage curItem  = itemPerId[tokenId];
        // curItem.state = State.Bidding;
        curItem.highestItemBidValue = 0;
        curItem.currentPrice = 0;
        curItem.reserve = basePrice;
        curItem.bidStartTime = int256(block.timestamp);
    }
    function extractAuctionFess() public payable {
        require(msg.sender == auctioneer, "Not Authorized to make this call");
        (bool success, ) = auctioneer.call{value: address(this).balance}("");
        require(success, "Payment failed");
    }
    // The following functions are overrides required by Solidity.
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}