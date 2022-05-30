/*

 _______       ___      .______       __  ___       _______      ___      .______      .___________. __    __  
|       \     /   \     |   _  \     |  |/  /      |   ____|    /   \     |   _  \     |           ||  |  |  | 
|  .--.  |   /  ^  \    |  |_)  |    |  '  /       |  |__      /  ^  \    |  |_)  |    `---|  |----`|  |__|  | 
|  |  |  |  /  /_\  \   |      /     |    <        |   __|    /  /_\  \   |      /         |  |     |   __   | 
|  '--'  | /  _____  \  |  |\  \----.|  .  \       |  |____  /  _____  \  |  |\  \----.    |  |     |  |  |  | 
|_______/ /__/     \__\ | _| `._____||__|\__\      |_______|/__/     \__\ | _| `._____|    |__|     |__|  |__| 
                                                                                                             
                             WWW.DARKEARTH.GG by Olympus Origin.
                            Coded by Javier Nieto & Jesús Sánchez.

*/

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Smart Contracts imports
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MysteryCapsule is ERC721Enumerable, AccessControlEnumerable {
 
    /**********************************************
     **********************************************
                    VARIABLES
    **********************************************                    
    **********************************************/
    using Counters for Counters.Counter;

    IERC20 tokenUSDC;

    string private _baseURIExtend;

    //OJO OJO OJO OJO OJO OJO!!!!!!!!!
    //Setear address a Polygon en producción
     //Mumbai
    address addrUSDC = 0xe11A86849d99F524cAC3E7A0Ec1241828e332C62;
    address aggregator = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada; // Mumbai MATIC/USD
    //Polygon
    //address addrUSDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    //address aggregator = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // Polygon MATIC/USD

    AggregatorV3Interface internal priceFeed;

    // Variables de suspensión de funcionalidades
    bool suspended = true; // Suspender funciones generales del SC
    bool suspendedWL = false; // Suspender función de WL
    bool publicSale = false; // Al poner a true se activa la venta publica (Sin restricciones)
    bool approvedTransfer = false; // Aprobar la transferencia de NFTs

    // Precio por cada capsula
    uint32 priceCapsule = 15; // USD natural
    
    // Cantidad por defecto por Wallet
    uint32 defaultMintAmount = 20;

    // Cantidad máxima de capsulas totales
    uint32 limitCapsules = 15000;
    uint32 limitPresale = 3000;
    uint32 limitRewards = 2288;
    uint32 presaleCounter = 0;
    
    Counters.Counter private rewardsCapsules;
    Counters.Counter private _tokenIdTracker;
    Counters.Counter private peopleWhitelisted;
    Counters.Counter private totalBurnedCapsules;
    
    //Adds support for OpenSea
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    address OpenSeaAddress = 0x58807baD0B376efc12F5AD86aAc70E78ed67deaE;

    //Roles of minter and burner
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PARTNER_ROLE = keccak256("PARTNER_ROLE");
    
    //Royaties address and amnount
    address payable private _royaltiesAddress;
    uint96 private _royaltiesBasicPoints;    
    uint96 private maxRoyaltiePoints = 1500;

    //Mapping from address to uin32. Set the amount of chest availables to buy
    //Works both as counter and as whitelist
    mapping(address => uint32) private available;

    mapping(address => uint32) private whitelistedSoFar;

    mapping(address => uint32) private burnedCapsules;

    // Free mints
    mapping(address => uint32) private freeMints;
    Counters.Counter private totalFreeMints;
    Counters.Counter private totalUsedFreeMints;

    struct detailPartnerMint {
        uint32 amount;
        uint32 price;
    }

    // Partner mints
    mapping(address => detailPartnerMint) partnerMints;

    // ---------------
    // Security
    // ---------------
    struct approveMap {
        address approveAddress;
        uint8 apprFunction;
    }

    mapping(address => bool) owners;
    mapping(address => approveMap) approvedFunction;
    Counters.Counter private _ownersTracker;
    
    /**********************************************
     **********************************************
                    CONSTRUCTOR
    **********************************************                    
    **********************************************/
    constructor() ERC721("Mystery Capsule", "MC") {

        // URI por defecto
        _baseURIExtend = "https://nft-hub.darkearth.gg/capsules/genesis/capsule_genesis.json";

        // Oraculo
        priceFeed = AggregatorV3Interface(aggregator);

        // Interfaz para pagos en USDC
        tokenUSDC = IERC20(addrUSDC);

        // El creador tiene todos los permisos
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(WHITELIST_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
       
        //Royaties address and amount
        _royaltiesAddress=payable(address(this)); //Contract creator by default
        _royaltiesBasicPoints=1000; //10% default

        // Multi-owner
        owners[0xfA3219264DB69fC37dD95E234E3807F5b6DD3cAE] = true;
        _ownersTracker.increment();
        owners[0x70d75a95E799D467e42eA6bC14dC9ca3E3dC5742] = true;
        _ownersTracker.increment();

    }

    // ------------------------------
    // AÑADIR ROLES
    // ------------------------------

    function addRole(address _to, bytes32 rol, bool option) external {
        require(checkApproved(_msgSender(), 23), "You have not been approved to run this function");
        
        if(option) {
            _grantRole(rol, _to);
        } else {
            _revokeRole(rol, _to);
        }
    }

    // ------------------------------
    // AÑADIR NUEVO PARTNER
    // ------------------------------

    function addPartner(address _to, uint32 amount, uint32 price) external {
        require(checkApproved(_msgSender(), 22), "You have not been approved to run this function");
        
        partnerMints[_to].amount = amount;
        partnerMints[_to].price = price;
        _grantRole(PARTNER_ROLE, _to);
    }

    // ------------------------------
    // AÑADIR WHITELIST
    // ------------------------------
    function addToWhitelist(address _to, uint32 amount) public {
        require(!suspendedWL, "The contract is temporaly suspended for Whitelist");
        require(whitelistedSoFar[_to]+amount <= defaultMintAmount, "Cannot assign more chests to mint than allowed");
        require(hasRole(WHITELIST_ROLE, _msgSender()), "Exception in WL: You do not have the whitelist role");

        // Añadir uno mas al contador de gente en la WL
        if(whitelistedSoFar[_to] == 0) peopleWhitelisted.increment();

        available[_to]+=amount;
        whitelistedSoFar[_to]+=amount;
        
    }

    function bulkDefaultAddToWhitelist(address[] memory _to) external {
        for (uint i=0; i < _to.length; i++)
            addToWhitelist(_to[i], defaultMintAmount);
    }

    // ------------------------------
    //  FREE MINTs
    // ------------------------------
    function bulkAddFreeMint(address[] memory _to, uint32[] memory amount) external {
        require(_to.length == amount.length, "Exception in buldAddFreeMint: Array sizes");
        require(checkApproved(_msgSender(), 2), "You have not been approved to run this function");
        
        for (uint i=0; i < _to.length; i++) {
            freeMints[_to[i]] += amount[i];
            totalFreeMints.increment();
        }
    }

    function bulkTakeFreeMint() external {
        require(!suspended, "The contract is temporaly suspended");
        require(freeMints[_msgSender()] > 0, "Exception in bulkTakeFreeMint: You dont have free mints");
        require(_tokenIdTracker.current() < limitCapsules + rewardsCapsules.current(), "There are no more capsules to mint... sorry!");

        for(uint i = 0; i < freeMints[_msgSender()]; i++) {

            _safeMint(_msgSender(), _tokenIdTracker.current());

            freeMints[_msgSender()] -= 1;
            _tokenIdTracker.increment();
            totalUsedFreeMints.increment();
        }
    }

    function getWalletFreeMints(address _to) view external returns (uint32) {
        return freeMints[_to];
    }

    function getTotalFreeMint() view external returns (uint256) {
        return totalFreeMints.current();
    }

    function getTotalUsedFreeMint() view external returns (uint256) {
        return totalUsedFreeMints.current();
    }

    // ------------------------------
    // MINTEO Y QUEMA DE CAPSULAS
    // ------------------------------

    function burn(uint256 tokenId) public virtual {
        require(!suspended, "The contract is temporaly suspended");
        require(ownerOf(tokenId) == _msgSender(), "Exception on Burn: Your are not the owner");

        burnedCapsules[ownerOf(tokenId)] += 1;
        totalBurnedCapsules.increment();

        _burn(tokenId);
    }

    function bulkBurn(uint256[] memory tokenIds) external {
        for(uint i = 0; i < tokenIds.length; i++)
            burn(tokenIds[i]);
    }
    
    function adminBulkBurn(uint256[] memory tokenIds) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "Exception in Burn: caller has no BURNER ROLE");
        for(uint i = 0; i < tokenIds.length; i++) {
            burnedCapsules[ownerOf(tokenIds[i])] += 1;
            totalBurnedCapsules.increment();
            _burn(tokenIds[i]);
        }
    }

    //Minter
    function mint(address _to) internal {
        require(!suspended, "The contract is temporaly suspended");
        require(_tokenIdTracker.current() < limitCapsules + rewardsCapsules.current(), "There are no more capsules to mint... sorry!");
        
        if(!hasRole(PARTNER_ROLE, _to)) {
            if(!publicSale){
                require(available[_to]> 0, "Exception in mint: You have not available capsules to mint");
                available[_to] = available[_to] - 1;
            }
        }

        _safeMint(_to, _tokenIdTracker.current());
        
        _tokenIdTracker.increment();
    } 

    function bulkMint(address _to, uint32 amount) internal {
        require(amount > 0, "Exception in bulkMint: Amount has to be higher than 0");
        for (uint i=0; i<amount; i++) {        
            mint(_to);
        }
    }

    function purchaseChest(uint32 amount) external payable {
        require(!suspended, "The contract is temporaly suspended");
        require(amount > 0, "Exception in purchaseChest: Amount has to be higher than 0");
        require(_tokenIdTracker.current() + amount < limitCapsules + rewardsCapsules.current(), "There are no more capsules to mint... sorry!");

        if(hasRole(PARTNER_ROLE, _msgSender())){
            require(partnerMints[_msgSender()].amount != 0, "Exception in purchasePartnerChest: Amount not config.");
            require(partnerMints[_msgSender()].price != 0, "Exception in purchasePartnerChest: Price not config.");
            require(partnerMints[_msgSender()].amount >= amount, "Exception in purchasePartnerChest: You are not allowed to buy this amount.");
            require(msg.value >= priceInMatic(partnerMints[_msgSender()].price) * amount, "Not enough funds sent!");
            if((partnerMints[_msgSender()].amount - amount) == 0) {
                _revokeRole(PARTNER_ROLE, _msgSender());
            }
            partnerMints[_msgSender()].amount -= amount;
        } else {
            require(msg.value >= priceInMatic(priceCapsule) * amount, "Not enough funds sent!");
            if(!publicSale){
                require(presaleCounter + 1 < limitPresale, "Exception in purchaseChest: Pre-Sale Sold-out");
                require(presaleCounter + amount < limitPresale, "Exception in purchaseChest: There are less capsules availables");
                require(available[_msgSender()]>=amount, "Exception in purchaseChest: cannot mint so many chests");
                presaleCounter += amount;
            }
        }

        //Mint the chest to the payer
        bulkMint(_msgSender(), amount);
    }

    function adminMint(address _to) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "Exception in mint: You dont have the minter role.");
        require(rewardsCapsules.current() + 1 < limitRewards, "Exception in adminMint: Limit reached.");
        
        _safeMint(_to, _tokenIdTracker.current());        
        _tokenIdTracker.increment();
        rewardsCapsules.increment();
    }

    function bulkAdminMint(address _to, uint32 amount) external {
        for (uint i=0; i<amount; i++) {        
            adminMint(_to);
        }
    }

    function bulkAdminPartnerMint(address _to, uint32 amount) external {
        require(amount > 0, "Exception in bulkAdminPartnerMint: Amount has to be higher than 0");
        require(hasRole(PARTNER_ROLE, _to), "Exception in mint: Target dont have PARTNER ROLE.");

        require(checkApproved(_msgSender(), 24), "You have not been approved to run this function.");

        for (uint i=0; i < amount; i++) {        
            _safeMint(_to, _tokenIdTracker.current());        
            _tokenIdTracker.increment();
        }
    }

    /**********************************************
     **********************************************
                PAGOS EN USDC
    **********************************************                    
    **********************************************/

    function AcceptPayment(uint32 amount) external {
        require(amount > 0, "Exception in AcceptPayment: Amount has to be higher than 0");
        require(!suspended, "The contract is temporaly suspended");
        require(_tokenIdTracker.current()+amount < limitCapsules + rewardsCapsules.current(), "There are no more capsules to mint... sorry!");

        uint256 convertPrice;

        if(hasRole(PARTNER_ROLE, _msgSender())){
            require(partnerMints[_msgSender()].amount != 0, "Exception in purchasePartnerChest: Amount not config.");
            require(partnerMints[_msgSender()].price != 0, "Exception in purchasePartnerChest: Price not config.");
            require(partnerMints[_msgSender()].amount >= amount, "Exception in purchasePartnerChest: You are not allowed to buy this amount.");
            if((partnerMints[_msgSender()].amount - amount) == 0) {
                _revokeRole(PARTNER_ROLE, _msgSender());
            }
            partnerMints[_msgSender()].amount -= amount;
            convertPrice = 1000000000000000000 * partnerMints[_msgSender()].price;
        } else {
            if(!publicSale){
                require(presaleCounter + 1 < limitPresale, "Exception in AcceptPayment: Pre-Sale Sold-out");
                require(presaleCounter+amount < limitPresale, "Exception in AcceptPayment: There are less capsules availables");
                require(available[_msgSender()]>=amount, "AcceptPayment: cannot mint so many chests");
                presaleCounter += amount;
            }

            convertPrice = 1000000000000000000 * priceCapsule;
        }

        bool success = tokenUSDC.transferFrom(_msgSender(), address(this), amount * convertPrice);
        require(success, "Could not transfer token. Missing approval?");

        bulkMint(_msgSender(), amount);
    }
   
    function GetAllowance() external view returns(uint256) {
       return tokenUSDC.allowance(_msgSender(), address(this));
    }

    function GetUsdcBalance() external view returns(uint256) {
       return tokenUSDC.balanceOf(address(this));
    }

    function withdrawUSDC(uint amount) external {
        require(checkApproved(_msgSender(), 18), "You have not been approved to run this function.");
        tokenUSDC.transfer(_msgSender(), amount);
    }
   
    // ------------------------------------------------------

    receive() external payable {}

    function withdraw(uint amount) external {
        require(checkApproved(_msgSender(), 19), "You have not been approved to run this function.");
        payable(_msgSender()).transfer(amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721Enumerable) {

        if(from != address(0) && to != address(0)) {
            require(approvedTransfer, "Transfers are temporarily suspended.");
        }

        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**********************************************
     **********************************************
                  GETTERs Y SETTERs
    **********************************************                    
    **********************************************/

    function getWhitelistedPeople() public view returns (uint256) {
        return peopleWhitelisted.current();
    }

    function getTotalBurnedCapsules() public view returns (uint256) {
        return totalBurnedCapsules.current();
    }

    function getChests(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++)
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);

        return tokenIds;
    }

    function getDefaultPrice() public view returns (uint32) {
        return priceCapsule;
    }

    function setDefaultPrice(uint32 newPrice) public {
        require(checkApproved(_msgSender(), 3), "You have not been approved to run this function.");
        priceCapsule=newPrice;
    }

    function setAggregator(address aggr) public {
        require(checkApproved(_msgSender(), 4), "You have not been approved to run this function.");
        aggregator=aggr;
    }

    function getAggregator() public view returns (address) {
        return aggregator;
    }

    function setOpenSeaAddress(address newAdd) public {
        require(checkApproved(_msgSender(), 5), "You have not been approved to run this function.");
        OpenSeaAddress = newAdd;
    }

    function getOpenSeaAddress() public view returns (address) {
        return OpenSeaAddress;
    }

    function setUSDCAddress(address usdc) public {
        require(checkApproved(_msgSender(), 6), "You have not been approved to run this function.");
        addrUSDC=usdc;
    }

    function getUSDCAddress() public view returns (address) {
        return addrUSDC;
    }

    function setLimitChest(uint32 limit) public {
        require(checkApproved(_msgSender(), 7), "You have not been approved to run this function.");
        limitCapsules=limit;
    }

    function getLimitChest() public view returns (uint32) {
        return limitCapsules;
    }

    function getLimitPresale() public view returns (uint32) {
        return limitPresale;
    }

    function getCounterPresale() public view returns (uint32) {
        return presaleCounter;
    }

    function getRewardsCounter() public view returns (uint256) {
        return rewardsCapsules.current();
    }

    function getTotalMintedChests() public view returns (uint256) {
        return _tokenIdTracker.current();
    }

    function getBurnedCapsules(address ownerId) public view returns (uint32) {
        return burnedCapsules[ownerId];
    }

    function getMintableChest(address ownerId) public view returns (uint256) {
        return available[ownerId];
    }

    function isWhitelisted(address ownerId) public view returns (bool) {
        return whitelistedSoFar[ownerId]>0;
    }

    function getTotalWhitelisted(address ownerId) public view returns (uint256) {
        return whitelistedSoFar[ownerId];
    }

    // Cantidad por defecto a mintear -> PRE-SALE
    function setDefaultMintAmount(uint32 defAmount) public {
        require(checkApproved(_msgSender(), 8), "You have not been approved to run this function.");
        defaultMintAmount=defAmount;
    }     

    // Cantidad limite de capsulas en Pre-Sale
    function setDefaultLimitPresale(uint32 defLimit) public {
        require(checkApproved(_msgSender(), 21), "You have not been approved to run this function.");
        limitPresale=defLimit;
    }

    function getDefaultMintAmount() public view returns (uint32) {
        return defaultMintAmount;
    }

    // Activar o desactivar la transferencia de NFTs
    function isApprovedTransfer() public view returns (bool) {
        return approvedTransfer;
    }

    function toggleApprovedTransfer(bool value) public {
        require(checkApproved(_msgSender(), 9), "You have not been approved to run this function.");
        approvedTransfer = value;
    }

    // Activar o desactivar la venta publica
    function isPublicSale() public view returns (bool) {
        return publicSale;
    }

    function enablePublicSale() public {
        require(checkApproved(_msgSender(), 10), "You have not been approved to run this function.");
        publicSale = true;
        priceCapsule = 20;
    }

    function suspendPublicSale() public {
        require(checkApproved(_msgSender(), 11), "You have not been approved to run this function.");
        publicSale = false;
        priceCapsule = 15;
    }

    // Suspender funcionalidades general del SC
    function isSuspend() public view returns (bool) {
        return suspended;
    }

    function toggleSuspend(bool value) public {
        require(checkApproved(_msgSender(), 12), "You have not been approved to run this function.");
        suspended = value;
    }

    // Suspender la función de añadir en WL
    function isSuspendWL() public view returns (bool) {
        return suspendedWL;
    }

    function toggleSuspendWL(bool value) public {
        require(checkApproved(_msgSender(), 13), "You have not been approved to run this function.");
        suspendedWL = value;
    }

    /**********************************************
     **********************************************
                   SPECIAL URI
    **********************************************                    
    **********************************************/

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIExtend;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(_baseURIExtend);
    }

    function setBaseURI(string memory newUri) external {
        require(checkApproved(_msgSender(), 20), "You have not been approved to run this function.");
        _baseURIExtend = newUri;
    }

    /**********************************************
     **********************************************
                   UTILITY FUNCTIONS
    **********************************************                    
    **********************************************/

    //Public wrapper of _exists
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    /**********************************************
     **********************************************
                   ERC721 FUNCTIONS
    **********************************************                    
    **********************************************/

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice ) external view returns ( address receiver, uint256 royaltyAmount) {
        if(exists(_tokenId))
            return(_royaltiesAddress, (_salePrice * _royaltiesBasicPoints)/10000);        
        return (address(0), 0); 
    }

    function setRoyaltiesAddress(address payable rAddress) public {
        require(checkApproved(_msgSender(), 14), "You have not been approved to run this function.");
        _royaltiesAddress=rAddress;
    }

    function setRoyaltiesBasicPoints(uint96 rBasicPoints) public {
        require(checkApproved(_msgSender(), 15), "You have not been approved to run this function");
        require(rBasicPoints <= maxRoyaltiePoints, "Royaties error: Limit reached");
        _royaltiesBasicPoints=rBasicPoints;
    }  

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControlEnumerable) returns (bool) {
        if(interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /**
    * Override isApprovedForAll to auto-approve OS's proxy contract
    */
    function isApprovedForAll(address _owner, address _operator) public override(ERC721, IERC721) view returns (bool isOperator) {
      // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == OpenSeaAddress) {
            return true;
        }
        
        // otherwise, use the default ERC721.isApprovedForAll()
        return super.isApprovedForAll(_owner, _operator);
    }

    /**********************************************
     **********************************************
           ORACULO OBTENER PRECIO EN MATIC
    **********************************************                    
    **********************************************/

    function decimals() public view returns (uint8) {
        return priceFeed.decimals();
    }

    function priceInMatic(uint32 price) public view returns (uint256) {
        return 1000000000000000000 * price * uint256(10 ** uint256(decimals())) / uint256(getLatestPrice());
    }

    function getLatestPrice() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }


    /*****************************************
                MULTI-OWNER SECURITY
    ******************************************/

    function existOwner(address addr) internal view returns(bool) {
        return owners[addr];
    }

    function checkApproved(address user, uint8 idFunc) internal returns(bool) {
        require(existOwner(user), "This is not a wallet from a owner");
        bool aprobado = false;
        if(approvedFunction[user].apprFunction == idFunc) {
            aprobado = true;
            clearApprove(user);
        }
        return aprobado;
    }

    function approveOwner(uint8 idFunc, address owner) external {
        require(existOwner(_msgSender()), "You are not owner");
        require(existOwner(owner), "This is not a wallet from a owner");
        require(_msgSender() != owner, "You cannot authorize yourself");
        approvedFunction[owner].apprFunction = idFunc;
        approvedFunction[owner].approveAddress = _msgSender();
    }

    function clearApprove(address owner) public {
        require(existOwner(_msgSender()), "You are not owner");
        require(existOwner(owner), "This is not a wallet from a owner");

        if (_msgSender() != owner) {
            require(approvedFunction[owner].approveAddress == _msgSender(), "You have not given this authorization");
        }

        approvedFunction[owner].apprFunction = 0;
        approvedFunction[owner].approveAddress = address(0);
    }

    /*****************************************
                CONTROL DE OWNERS
    ******************************************/

    function addOwner(address newOwner) public {
        require(checkApproved(_msgSender(), 16), "You have not been approved to run this function");
        
        owners[newOwner] = true;
        _ownersTracker.increment();
    }

    function delOwner(address addr) public {
        require(checkApproved(_msgSender(), 17), "You have not been approved to run this function");

        owners[addr] = false;
        _ownersTracker.decrement();
        approvedFunction[addr].apprFunction = 0;
        approvedFunction[addr].approveAddress = address(0);
    }

    function getTotalOwners() public view returns(uint){
        return _ownersTracker.current();
    }
}