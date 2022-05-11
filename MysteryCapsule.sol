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
pragma solidity ^0.8.0;

// Smart Contracts imports
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MysteryCapsule is ERC721Enumerable, AccessControlEnumerable, Ownable {

    /*
    ---------------------------
           TODO TODO TODO
    ---------------------------

    - Accept USDC (Revisar seguridad)

    - Withdraw USDC (Revisar seguridad)

    - Getter total personas en la WL (Revisar si está bien hecho y seguridad)

    - Revisar bool publicSale para venta pública (Agujeros de seguridad)

    - Revisar bool suspendedWL para suspender añadir WL
        Se ha separado de la variable suspend general para poder suspender el SC (minteo)
        pero poder añadir WL a la gente. Así podrán ver la web sin interactuar con ella.

    - Revisar bool approvedTransfer para permitir las transferencias de NFTs
 
    /**********************************************
     **********************************************
                    VARIABLES
    **********************************************                    
    **********************************************/

    IERC20 tokenUSDC;

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
    bool suspended = false; // Suspender funciones generales del SC
    bool suspendedWL = false; // Suspender función de WL
    bool publicSale = false; // Al poner a true se activa la venta publica (Sin restricciones)
    bool approvedTransfer = false; // Aprobar la transferencia de NFTs

    // Precio por cada capsula
    uint256 priceCapsule = 15; // USD natural
    
    // Cantidad por defecto por Wallet
    uint32 defaultMintAmount = 20;

    // Cantidad máxima de capsulas totales
    uint256 limitCapsules = 15000;
    uint256 hiddenCapsules = 0;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;
    Counters.Counter private peopleWhitelisted;
    Counters.Counter private totalBurnedCapsules;
    
    //Adds support for OpenSea
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    address OpenSeaAddress = 0x58807baD0B376efc12F5AD86aAc70E78ed67deaE;

    //Roles of minter and burner
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    
    //Royaties address and amnount
    address payable private _royaltiesAddress;
    uint96 private _royaltiesBasicPoints;    


    //Mapping from address to uin32. Set the amount of chest availables to buy
    //Works both as counter and as whitelist
    mapping(address => uint32) private available;

    mapping(address => uint32) private whitelistedSoFar;

    mapping(address => uint32) private burnedCapsules;
    
    /**********************************************
     **********************************************
                    CONSTRUCTOR
    **********************************************                    
    **********************************************/
    constructor() ERC721("Mystery Capsule", "MC") {

        // Oraculo
        priceFeed = AggregatorV3Interface(aggregator);

        // Interfaz para pagos en USDC
        tokenUSDC = IERC20(addrUSDC);

        // El creador tiene todos los permisos
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(WITHDRAW_ROLE, _msgSender());

        //Royaties address and amount
        _royaltiesAddress=payable(address(this)); //Contract creator by default
        _royaltiesBasicPoints=500; //5% default

    }

    /**********************************************
     **********************************************
                    MINTER
              SETTERS AND GETTERS
    **********************************************                    
    **********************************************/

    // ------------------------------
    // AÑADIR WHITELIST
    // ------------------------------
    function addToWhitelist(address _to, uint32 amount) public {
        require(!suspendedWL, "The contract is temporaly suspended for Whitelist");
        require(whitelistedSoFar[_to]+amount <= defaultMintAmount, "Cannot assign more chests to mint than allowed");
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Exception in WL: You dont have the admin role.");

        // Añadir uno mas al contador de gente en la WL
        if(whitelistedSoFar[_to] == 0) peopleWhitelisted.increment();

        available[_to]+=amount;
        whitelistedSoFar[_to]+=amount;
        
    }

    function bulkAddToWhitelist(address[] memory _to, uint32[] memory amount) public {
        require(_to.length == amount.length, "The addresses array has no same length than amount array");
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Exception in WL bulk: You dont have the admin role.");

        for (uint i=0; i<_to.length; i++)
            addToWhitelist(_to[i], amount[i]);
    }

    function bulkDefaultAddToWhitelist(address[] memory _to) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Exception in WL bulk default: You dont have the admin role.");

        for (uint i=0; i<_to.length; i++)
            addToWhitelist(_to[i], defaultMintAmount);
    }

    // ------------------------------
    // MINTEO Y QUEMA DE CAPSULAS
    // ------------------------------

    function burn(uint256 tokenId) public virtual {
        //require(hasRole(BURNER_ROLE, _msgSender()), "Exception in Burn: caller has no BURNER ROLE");
        require(ownerOf(tokenId) == _msgSender(), "Exception on Burn:Your are not the owner");

        // Añadir una capsula mas a quemados
        // No se puede hacer soFar-available por que no cuenta los publicSale
        burnedCapsules[ownerOf(tokenId)] += 1;
        totalBurnedCapsules.increment();

        _burn(tokenId);
    }

    function bulkBurn(uint256[] memory tokenIds) public virtual {
        //require(hasRole(BURNER_ROLE, _msgSender()), "Exception in bulkBurn: caller has no BURNER ROLE");

        for(uint i = 0; i < tokenIds.length; i++){
            burn(tokenIds[i]);
        }
    }

    //Minter
    function mint(address _to) internal {
        require(!suspended, "The contract is temporaly suspended");
        require(available[_to] > 0, "Exception in mint: Dont have capsules to mint.");
        require(_tokenIdTracker.current() <= limitCapsules + hiddenCapsules, "There are no more capsules to mint... sorry!");
        
        super._mint(_to, _tokenIdTracker.current());
        
        available[_to] = available[_to] - 1;
        _tokenIdTracker.increment();

    } 

    function bulkMint(address _to, uint32 amount) internal {
        //require(!suspended, "The contract is temporaly suspended");

        for (uint i=0; i<amount; i++) {        
            mint(_to);
        }
    }

    function purchaseChest(uint32 amount) external payable {        
        require(!suspended, "The contract is temporaly suspended");
        //require(!publicSale, "Exception MATIC: public sale opened");
        require(msg.value >= priceInMatic() * amount, "Not enough funds sent!");
        require(_tokenIdTracker.current()+amount <= limitCapsules + hiddenCapsules, "There are no more capsules to mint... sorry!");

        if(publicSale){
            available[_msgSender()] += amount;
        } else {
            require(available[_msgSender()]>=amount, "Exception: cannot mint so many chests");
        }

        //Mint the chest to the payer
        bulkMint(_msgSender(), amount);
    }

    /*
    function publicPurchaseChest(uint32 amount) external payable {        
        require(!suspended, "The contract is temporaly suspended");
        require(publicSale, "Exception: public sale not opened");
        require(msg.value>=priceInMatic() * amount, "Not enough funds sent!");
        require(_tokenIdTracker.current()+amount <= limitCapsules + hiddenCapsules, "There are no more capsules to mint... sorry!");
        
        available[_msgSender()]+=amount;
        
        //Mint the chest to the payer
        bulkMint(_msgSender(), amount);
    }
    */

    function adminMint(address _to) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "Exception in mint: You dont have the minter role.");
        
        super._mint(_to, _tokenIdTracker.current());        
        _tokenIdTracker.increment();
        hiddenCapsules=hiddenCapsules+1;
    } 

    function bulkAdminMint(address _to, uint32 amount) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "Exception in mint: You dont have the minter role.");
        
        for (uint i=0; i<amount; i++) {        
            adminMint(_to);
        }
    }

    /**********************************************
     **********************************************
                PAGOS EN USDC
    **********************************************                    
    **********************************************/

    function AcceptPayment(uint32 amount) public {
        require(!suspended, "The contract is temporaly suspended");
        //require(!publicSale, "Exception: public sale opened");
        require(_tokenIdTracker.current()+amount <= limitCapsules + hiddenCapsules, "There are no more capsules to mint... sorry!");

        if(publicSale){
            available[_msgSender()]+=amount;
        } else {
            require(available[_msgSender()] >= amount, "Exception: cannot mint so many chests");
        }
       
        uint256 convertPrice = 1000000000000000000 * priceCapsule;

        bool success = tokenUSDC.transferFrom(_msgSender(), address(this), amount * convertPrice);
        require(success, "Could not transfer token. Missing approval?");

        bulkMint(_msgSender(), amount);
    }

    /*
    function publicAcceptPayment(uint32 amount) public {
        require(!suspended, "The contract is temporaly suspended");
        require(publicSale, "Exception: public sale not opened");
        require(_tokenIdTracker.current()+amount <= limitCapsules + hiddenCapsules, "There are no more capsules to mint... sorry!");
        
        uint256 convertPrice = 1000000000000000000 * priceCapsule;

        bool success = tokenUSDC.transferFrom(_msgSender(), address(this), amount * convertPrice);
        require(success, "Could not transfer token. Missing approval?");

        available[_msgSender()]+=amount;
        bulkMint(_msgSender(), amount);
    }
    */
   
    function GetAllowance() public view returns(uint256) {
       return tokenUSDC.allowance(msg.sender, address(this));
    }

    function GetUsdcBalance() public view returns(uint256) {
       return tokenUSDC.balanceOf(address(this));
    }

    function withdrawUSDC(uint amount) external {
        require(hasRole(WITHDRAW_ROLE, _msgSender()), "Exception: must have withdraw role to retire funds");
        tokenUSDC.transfer(_msgSender(), amount);
    }
   
    // ------------------------------------------------------

    receive() external payable {}

    function withdraw(uint amount) external {
        require(hasRole(WITHDRAW_ROLE, _msgSender()), "Exception: must have withdraw role to retire funds");
        payable(_msgSender()).transfer(amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721Enumerable) {

        if(from != address(0) && to != address(0)) {
            require(approvedTransfer, "Sorry, you have to wait for the sale to end to transfer these NFTs.");
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

    function getDefaultPrice() public view returns (uint256) {
        return priceCapsule;
    }

    function setDefaultPrice(uint256 newPrice) public onlyOwner {
        priceCapsule=newPrice;
    }

    function setAggregator(address aggr) public onlyOwner {
        aggregator=aggr;
    }

    function getAggregator() public view returns (address) {
        return aggregator;
    }

    function setOpenSeaAddress(address newAdd) public onlyOwner {
        OpenSeaAddress = newAdd;
    }

    function getOpenSeaAddress() public view returns (address) {
        return OpenSeaAddress;
    }

    function setUSDCAddress(address usdc) public onlyOwner {
        addrUSDC=usdc;
    }

    function getUSDCAddress() public view returns (address) {
        return addrUSDC;
    }

    function setLimitChest(uint256 limit) public onlyOwner {
        limitCapsules=limit;
    }

    function getLimitChest() public view returns (uint256) {
        return limitCapsules;
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
    function setDefaultMintAmount(uint32 defAmount) public onlyOwner {
        defaultMintAmount=defAmount;
    }     

    function getDefaultMintAmount() public view returns (uint32) {
        return defaultMintAmount;
    }

    // Activar o desactivar la transferencia de NFTs
    function isApprovedTransfer() public view returns (bool) {
        return approvedTransfer;
    }

    function enableTransfers() public onlyOwner {
        approvedTransfer = true;
    }

    function suspendTransfers() public onlyOwner {
        approvedTransfer = false;
    }

    // Activar o desactivar la venta publica
    function isPublicSale() public view returns (bool) {
        return publicSale;
    }

    function enablePublicSale() public onlyOwner {
        publicSale = true;
    }

    function suspendPublicSale() public onlyOwner {
        publicSale = false;
    }

    // Suspender funcionalidades general del SC
    function isSuspend() public view returns (bool) {
        return suspended;
    }

    function suspend() public onlyOwner {
        suspended = true;
    }

    function resume() public onlyOwner {
        suspended = false;
    }

    // Suspender la función de añadir en WL
    function isSuspendWL() public view returns (bool) {
        return suspendedWL;
    }

    function suspendWL() public onlyOwner {
        suspendedWL = true;
    }

    function resumeWL() public onlyOwner {
        suspendedWL = false;
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

    
    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nfthub.darkearth.gg/capsules/genesis/";
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice ) external view returns ( address receiver, uint256 royaltyAmount) {
        if(exists(_tokenId))
            return(_royaltiesAddress, (_salePrice * _royaltiesBasicPoints)/10000);        
        return (address(0), 0); 
    }

    function setRoyaltiesAddress(address payable rAddress) public onlyOwner {
        _royaltiesAddress=rAddress;
    }

    function setRoyaltiesBasicPoints(uint96 rBasicPoints) public onlyOwner {
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

    function priceInMatic() public view returns (uint256) {
        return 1000000000000000000 * priceCapsule * uint256(10 ** uint256(decimals())) / uint256(getLatestPrice());
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
}