//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Storage is
    ERC721URIStorage,
    ReentrancyGuard,
    Ownable,
    IERC721Receiver
{
    constructor() ERC721("Skywalker", "SKY") {}

    using Counters for Counters.Counter;

    uint256 public checkAmount;

    Counters.Counter private _tokenIds;
    Counters.Counter private _totalAmount;
    Counters.Counter private _itemsSold;
    Counters.Counter public _offerPriceId;

    uint256 private _mintPrice;
    uint256 private _auctionDuration;
    uint256 private _auctionMinimalBidAmount;

    event NFTAddressChanged(address oldAddress, address newAddress);
    event MintPriceUpgraded(uint256 oldPrice, uint256 newPrice, uint256 time);
    event Burned(uint256 indexed tokenId, address sender, uint256 currentTime);
    event EventCanceled(uint256 indexed tokenId, address indexed seller);

    event AuctionMinimalBidAmountUpgraded(
        uint256 newAuctionMinimalBidAmount,
        uint256 time
    );
    event AuctionDurationUpgraded(
        uint256 newAuctionDuration,
        uint256 currentTime
    );
    event MarketItemCreated(
        uint256 indexed itemId,
        address indexed owner,
        uint256 timeOfCreation
    );
    event ListedForSale(
        uint256 indexed itemId,
        uint256 price,
        uint256 listedTime,
        address indexed owner,
        address indexed seller
    );
    event Sold(
        uint256 indexed itemId,
        uint256 price,
        uint256 soldTime,
        address indexed seller,
        address indexed buyer
    );
    event StartAuction(
        uint256 indexed itemId,
        uint256 startPrice,
        address seller,
        uint256 listedTime
    );
    event BidIsMade(
        uint256 indexed tokenId,
        uint256 price,
        uint256 numberOfBid,
        address indexed bidder
    );
    event PositiveEndAuction(
        uint256 indexed itemId,
        uint256 endPrice,
        uint256 bidAmount,
        uint256 endTime,
        address indexed seller,
        address indexed winner
    );
    event NegativeEndAuction(
        uint256 indexed itemId,
        uint256 bidAmount,
        uint256 endTime
    );
    event NFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    enum TokenStatus {
        DEFAULT,
        ACTIVE,
        ONSELL,
        ONAUCTION,
        BURNED
    }
    enum SaleStatus {
        DEFAULT,
        ACTIVE,
        SOLD,
        CANCELLED
    }
    enum AuctionStatus {
        DEFAULT,
        ACTIVE,
        SUCCESSFUL_ENDED,
        UNSUCCESSFULLY_ENDED
    }
    struct SaleOrder {
        address payable creator;
        address payable seller;
        address payable owner;
        uint256 price;
        uint256 royalties;
        SaleStatus status;
    }
    struct AuctionOrder {
        uint256 startPrice;
        uint256 startTime;
        uint256 currentPrice;
        uint256 bidAmount;
        address payable owner;
        address payable seller;
        address payable lastBidder;
        AuctionStatus status;
    }

    struct FixedAuction {
        uint256 offerId;
        uint256 offerPrice;
        address payable bidderAddress;
    }

    mapping(uint256 => TokenStatus) private _idToItemStatus;
    mapping(uint256 => SaleOrder) private _idToOrder;
    mapping(uint256 => AuctionOrder) private _idToAuctionOrder;
    mapping(uint256 => mapping(uint256 => FixedAuction)) public _idToFixedOrder;

    // mapping(uint256 => FixedAuction) private _idToFixedOrder;

    modifier isActive(uint256 tokenId) {
        require(
            _idToItemStatus[tokenId] == TokenStatus.ACTIVE,
            "Marketplace: This NFT has already been put up for sale or auction!"
        );
        _;
    }
    modifier auctionIsActive(uint256 tokenId) {
        require(
            _idToAuctionOrder[tokenId].status == AuctionStatus.ACTIVE,
            "Marketplace: Auction already ended!"
        );
        _;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function _feeDenominator() internal pure virtual returns (uint96) {
        return 10000;
    }

    function createItem(string memory tokenURI, uint256 _royalties) external {
        _totalAmount.increment();
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        SaleOrder storage order = _idToOrder[tokenId];
        // _idToOrder[tokenId] = SaleOrder;
        order.royalties = _royalties;
        order.creator = payable(msg.sender);
        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI);
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;
        emit MarketItemCreated(tokenId, msg.sender, block.timestamp);
    }

    function listItem(uint256 tokenId, uint256 price)
        external
        isActive(tokenId)
    {
        SaleOrder storage order = _idToOrder[tokenId];
        address owner = ownerOf(tokenId);
        safeTransferFrom(owner, address(this), tokenId);
        _idToItemStatus[tokenId] = TokenStatus.ONSELL;
        order.seller = payable(msg.sender);
        order.owner = payable(owner);
        order.price = price;
        order.status = SaleStatus.ACTIVE;
        emit ListedForSale(tokenId, price, block.timestamp, owner, msg.sender);
    }

    function getRoyaltyAmount(uint256 nftPrice, uint256 _royaltyPercentageFee)
        internal
        pure
        returns (uint256)
    {
        uint256 amount = SafeMath.div(
            SafeMath.mul(nftPrice, _royaltyPercentageFee),
            _feeDenominator()
        );
        return amount;
    }

    function test(uint256 tokenId) external payable {
        SaleOrder storage order = _idToOrder[tokenId];
        uint256 royaltyFee = getRoyaltyAmount(order.price, order.royalties);
        checkAmount = royaltyFee;
    }

    function buyItem(uint256 tokenId) external payable nonReentrant {
        SaleOrder storage order = _idToOrder[tokenId];
        require(order.status == SaleStatus.ACTIVE, "Item is not on sale");
        require(
            msg.value >= order.price,
            "price should be equal to price of NFT"
        );
        uint256 royaltyFee = getRoyaltyAmount(order.price, order.royalties);
        address payable sendTo = order.seller;

        (bool sent, ) = sendTo.call{value: order.price}("");
        require(sent, "Transection failed while sending ethers to seller");
        (bool send, ) = order.creator.call{value: royaltyFee}("");
        require(
            send,
            "Transection failed while sending royaltyAmount to creator"
        );
        _transfer(address(this), msg.sender, tokenId);
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;
        _itemsSold.increment();
        emit Sold(
            tokenId,
            order.price,
            block.timestamp,
            order.seller,
            msg.sender
        );
    }

    function cancel(uint256 tokenId) external nonReentrant {
        SaleOrder storage order = _idToOrder[tokenId];
        require(
            msg.sender == order.owner || msg.sender == order.seller,
            "Marketplace: You don't have the authority to cancel the sale of this token!"
        );
        require(
            _idToOrder[tokenId].status == SaleStatus.ACTIVE,
            "Marketplace: The token wasn't on sale"
        );
        _transfer(address(this), order.owner, tokenId);
        // NFT.safeTransferFrom(address(this), order.owner, tokenId);
        order.status = SaleStatus.CANCELLED;
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;
        emit EventCanceled(tokenId, msg.sender);
    }

    function makeOffer(uint256 tokenId, uint256 offerPrice)
        external
        payable
        nonReentrant
    {
        _offerPriceId.increment();
        uint256 offerPriceId = _offerPriceId.current();

        SaleOrder storage saleOrder = _idToOrder[tokenId];
        require(saleOrder.status == SaleStatus.ACTIVE, "Item is not on sale");
        require(msg.value >= offerPrice, "insufficent funds");
        _idToFixedOrder[tokenId][offerPriceId] = FixedAuction(
            offerPriceId,
            offerPrice,
            payable(msg.sender)
        );
    }

    function acceptOffer(uint256 tokenId, uint256 offerId) external payable {
        SaleOrder storage order = _idToOrder[tokenId];
        FixedAuction storage fixedAuction = _idToFixedOrder[tokenId][offerId];
        // sending offerPrice  to seller address
        (bool seller, ) = order.seller.call{value: fixedAuction.offerPrice}("");
        require(seller, "failed while sending ether to seller address");
        //transfering the ownership to bidderAddress from contract address
        _transfer(address(this), fixedAuction.bidderAddress, tokenId);

        fixedAuction.bidderAddress = payable(address(0));
        fixedAuction.offerPrice = 0;
        //returning all the remaning offerPrice ether to thier bidderAddress
        for (uint256 i = 1; i <= _offerPriceId.current(); i++) {
            FixedAuction storage recipents = _idToFixedOrder[tokenId][i];
            // require(recipents.bidderAddress!= address(0), "EMpty address");
            if (recipents.offerPrice == 0) {
                continue;
            }
            (bool sent, ) = recipents.bidderAddress.call{
                value: recipents.offerPrice
            }("");
            require(sent, "failed while returning ether");
        }
    }

    function editOffer(
        uint256 _tokenId,
        uint256 _offerId,
        uint256 _offerPrice
    ) external payable nonReentrant {
        FixedAuction storage fixedAuction = _idToFixedOrder[_tokenId][_offerId];
        require(
            fixedAuction.bidderAddress == msg.sender,
            "You are not authorized to edit this bid"
        );
        uint256 oldPrice = fixedAuction.offerPrice;
        require(msg.value >= _offerPrice);
        fixedAuction.offerPrice = _offerPrice+oldPrice;
    }

    function withDrawOfferPrice(uint256 _tokenId , uint256 _offerId) external payable nonReentrant{
        FixedAuction storage fixedAuction = _idToFixedOrder[_tokenId][_offerId];
        require(
            fixedAuction.bidderAddress == msg.sender,
            "You are not authorized to with this bid"
        );
        (bool seller,) = fixedAuction.bidderAddress.call{value: fixedAuction.offerPrice}("");
        require(seller , "Transection failed while withdrawing ethers");
        fixedAuction.bidderAddress = payable(address(0));
        fixedAuction.offerPrice = 0;
    }
}
