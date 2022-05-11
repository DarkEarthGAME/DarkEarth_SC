/*

 _______       ___      .______       __  ___       _______      ___      .______      .___________. __    __  
|       \     /   \     |   _  \     |  |/  /      |   ____|    /   \     |   _  \     |           ||  |  |  | 
|  .--.  |   /  ^  \    |  |_)  |    |  '  /       |  |__      /  ^  \    |  |_)  |    `---|  |----`|  |__|  | 
|  |  |  |  /  /_\  \   |      /     |    <        |   __|    /  /_\  \   |      /         |  |     |   __   | 
|  '--'  | /  _____  \  |  |\  \----.|  .  \       |  |____  /  _____  \  |  |\  \----.    |  |     |  |  |  | 
|_______/ /__/     \__\ | _| `._____||__|\__\      |_______|/__/     \__\ | _| `._____|    |__|     |__|  |__| 
                                                                                                             
                                WWW.DARKEARTH.GG by Olympus Origin.
                                    By Jesús Sánchez Fernández

*/

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Smart Contracts imports
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract CardsV2 is ERC721Enumerable, AccessControlEnumerable, Ownable {

    using Strings for uint256;
    /**********************************************
     **********************************************
                       VARIABLES
    **********************************************                    
    **********************************************/

    // Variables de suspensión de funcionalidades
    bool suspended = false; // Suspender funciones generales del SC

    // Walet para comprobar la firma
    address private signAddr;

    string private _baseURIExtend;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;
    
    //Adds support for OpenSea
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    address OpenSeaAddress = 0x58807baD0B376efc12F5AD86aAc70E78ed67deaE;

    //Roles of minter and burner
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant EXPANSION_ROLE = keccak256("EXPANSION_ROLE");
    
    
    //Royaties address and amnount
    address payable private _royaltiesAddress;
    uint96 private _royaltiesBasicPoints;    

    // --> Control del Supply
    Counters.Counter private _typesTracker;

    struct nftSup {
        uint256 generalIdCard; // ID General de la carta
        uint256 sMax;
        Counters.Counter sNow;
        Counters.Counter burned;
    }

    // Mapeo tipo -> Supply
    mapping(uint256 => nftSup) private nftSupply;

    // --> Control tokenId + INFO
    struct nftInfo {
        uint256 idCard; // ID General de la carta
        uint256 serialNumber;
        uint256 tipo;
        bool usado;
    }

    mapping(uint256 => nftInfo) private tokenInfo;

    // Mapeo Wallet -> (Tipo -> Cantidad)
    //mapping(address => mapping(uint256 => uint256)) private typeBalance;

    // Controlar la TX que ya se han registrado
    mapping(string => bool) private txRewarded;

    // Recompensas
    Counters.Counter private _rewardsTracker;

    struct reward {
        uint256[] nftNeeds;
        uint256[] nftReward;
        uint256 limit;
        Counters.Counter limitCounter;
        bool active;
        //address[] walletsClaimed;
    }

    mapping(uint256 => reward) private rewardsCollect;
    
    /**********************************************
     **********************************************
                    CONSTRUCTOR
    **********************************************                    
    **********************************************/
    constructor() ERC721("Dark Earth Collection", "DE") {

        // URI por defecto
        _baseURIExtend = "https://nfthub.darkearth.gg/cards/";

        // Dirección que comprueba la firma
        signAddr = _msgSender();

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
                    SUPPLY SYSTEM
    **********************************************                    
    **********************************************/

    // Añadir Supply individual
    function addSupply(uint idC, uint tipo, uint amount) public onlyOwner {

        nftSupply[tipo].generalIdCard = idC;
        nftSupply[tipo].sMax = amount;
        //nftSupply[tipo].sNow = 0;

    }


    // [1,1,2,2,2,3,3,4,4,5,5,6,6,7,7,8,8,8,9,9,10,10,10]
    // [1,57,2,76,86,3,41,4,58,5,42,6,59,7,43,8,68,82,9,44,10,69,92]
    // [100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100]

    // Añadir supply masivo
    function addBulkSupply(uint[] memory idGeneral, uint[] memory tipos, uint[] memory amount) public onlyOwner {

        for(uint i = 0; i < tipos.length; i++) {
            addSupply(idGeneral[i], tipos[i], amount[i]);
        }

    }

    // Tipo 1
    // [1,57]
    // [100, 500]

    // Añadir supply masivo por tipo general
    function addBulkSupplyByGeneralType(uint idGeneral, uint[] memory tipos, uint[] memory amount) public onlyOwner {

        for(uint i = 0; i < tipos.length; i++) {
            addSupply(idGeneral, tipos[i], amount[i]);
        }

    }

    function getGeneralIdCardSupply(uint tipo) public view returns(uint) {
        return nftSupply[tipo].generalIdCard;
    }

    function getMaxSupply(uint tipo) public view returns(uint) {
        return nftSupply[tipo].sMax;
    }

    function getNowSupply(uint tipo) public view returns(uint) {
        return nftSupply[tipo].sNow.current();
    }

    // Comprobar el Supply de cada carta
    function checkSupply(uint tipo) internal view returns (bool) {

        bool respuesta = false;

        // Representa que este tipo no se ha inicializado
        if(nftSupply[tipo].sMax == 0) {

            respuesta = false;

        // Cuando ya el valor es 1 (inicializado) empiezo a comprobar Supply
        } else if(nftSupply[tipo].sNow.current() < nftSupply[tipo].sMax) {

            respuesta = true;

        }

        return respuesta;

    }

    /**********************************************
     **********************************************
                        BURNER
    **********************************************                    
    **********************************************/

    function burn(uint256 tokenId) public virtual {
        if(!hasRole(BURNER_ROLE, _msgSender())) {
            require(ownerOf(tokenId) == _msgSender(), "Exception on Burn: Your are not the owner");
        }

        uint tipo = getTokenType(tokenId);
        nftSupply[tipo].burned.increment();

        _burn(tokenId);
    }

    function bulkBurn(uint256[] memory tokenIds) public virtual {
        //require(hasRole(BURNER_ROLE, _msgSender()), "Exception in bulkBurn: caller has no BURNER ROLE");

        for(uint i = 0; i < tokenIds.length; i++){
            burn(tokenIds[i]);
        }
    }

    /**********************************************
     **********************************************
                    MINTER
              SETTERS AND GETTERS
    **********************************************                    
    **********************************************/

    function mintCards(uint[] memory cardsIds, string[] memory txIds, bytes memory firma) public {

        require(!suspended, "The contract is temporaly suspended.");
        require(isSigValid(generaMensaje(cardsIds, txIds), firma), "SIGNATURE ERROR: What are you trying to do?");
        require(checkLength(cardsIds, txIds), "LENGTH ERROR: Data malformed");
        require(!checkTx(txIds), "ERROR: This transaction is already in our system.");

        for(uint i = 0; i < cardsIds.length; i++) {
            require(checkSupply(cardsIds[i]), "SUPPLY ERROR: Not enough of this type.");
            mint(_msgSender(), cardsIds[i], getGeneralIdCardSupply(cardsIds[i]));
        }
    }

    function mintRewardCards(address _to, uint[] memory cardsIds) internal {
        require(!suspended, "The contract is temporaly suspended.");

        for(uint i = 0; i < cardsIds.length; i++) {
            require(checkSupply(cardsIds[i]), "SUPPLY ERROR: Not enough of this type.");
            mint(_to, cardsIds[i], getGeneralIdCardSupply(cardsIds[i]));
        }
    }

    function adminMint(address _to, uint[] memory cardsIds) public {
        require(!suspended, "The contract is temporaly suspended.");
        require(hasRole(MINTER_ROLE, _msgSender()), "You dont have Minter role! Sorry");

        for(uint i = 0; i < cardsIds.length; i++) {
            require(checkSupply(cardsIds[i]), "SUPPLY ERROR: Not enough of this type.");
            mint(_to, cardsIds[i], getGeneralIdCardSupply(cardsIds[i]));
        }
    }

    function mint(address _to, uint _tipo, uint _idCard) internal {
        require(!suspended, "The contract is temporaly suspended"); 

        // Aumento el Supply Actual de ese tipo
        nftSupply[_tipo].sNow.increment(); 

        // Guardo ID del token -> Tipo
        tokenInfo[_tokenIdTracker.current()].serialNumber = nftSupply[_tipo].sNow.current();
        tokenInfo[_tokenIdTracker.current()].idCard = _idCard;
        tokenInfo[_tokenIdTracker.current()].tipo = _tipo;
        tokenInfo[_tokenIdTracker.current()].usado = false;

        // Minteo la carta
        _mint(_to, _tokenIdTracker.current());

        // Aumento el contador
        _tokenIdTracker.increment();

    } 

    /*
    receive() external payable {}

    function withdraw(uint amount) external {
        require(hasRole(WITHDRAW_ROLE, _msgSender()), "Exception: must have withdraw role to retire funds");
        payable(_msgSender()).transfer(amount);
    }
    */

    /**********************************************
     **********************************************
                  SIGN SECURITY
    **********************************************                    
    **********************************************/

    // Genera el mensaje para poder verificar la firma
    function generaMensaje(uint[] memory cardsIds, string[] memory txIds) internal pure returns (string memory) {

        string memory mensaje;
        string memory aux;

        for(uint i = 0; i < cardsIds.length;i++){

            aux = string(abi.encodePacked("C", Strings.toString(cardsIds[i]),","));
            mensaje = string(abi.encodePacked(mensaje, aux));

        }

        for(uint j = 0; j < txIds.length; j++) {

            if(j == txIds.length-1) {
                mensaje = string(abi.encodePacked(mensaje, txIds[j]));
            } else {
                aux = string(abi.encodePacked(txIds[j],","));
                mensaje = string(abi.encodePacked(mensaje, aux));
            }
            
        }

        return mensaje;

    }

    // Comprobar firma
    function isSigValid (string memory message, bytes memory signature) internal view returns(bool) {
        return signAddr == ECDSA.recover(
            keccak256(abi.encodePacked(message)),
            signature
        );
    }

    // Comprueba que se corresponden los tamaños del array
    // 8 cardsIds por cada txId
    function checkLength(uint[] memory cardsIds, string[] memory txIds) internal pure returns (bool) {
        bool respuesta = false;

        if((cardsIds.length % 8) != 0){
            respuesta = false;
        } else {
            if((cardsIds.length/8) == txIds.length) {
                respuesta = true;
            } else {
                respuesta = false;
            }
        }

        return respuesta;
    }

    // Comparar dos Strings
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    // Comprueba que la transacción no esté en el sistema
    // Si no la está añade
    function checkTx(string[] memory txIds) internal returns(bool) {

        string memory aux;
        bool respuesta = false;

        if(txIds.length == 1) {

            aux = txIds[0];
            if(txRewarded[aux]) respuesta = true;
            txRewarded[aux] = true;
            
        } else {

            aux = txIds[0];
            uint i = 1;

            while(!respuesta && i < txIds.length) {

                if(txRewarded[aux]) {

                    respuesta = true;

                } else {

                    if(i == txIds.length-1){

                        txRewarded[txIds[i]] = true;

                    } else {

                        if(!compareStrings(aux, txIds[i])){
                            txRewarded[aux] = true;
                        }

                    }
                    
                }

                aux = txIds[i];
                i += 1;
            }
            
        }

        return respuesta;
    }

    /**********************************************
     **********************************************
                     REWARDS ZONE
    **********************************************                    
    **********************************************/

    function addReward(uint256[] memory idCardNeeds, uint256[] memory rewards, uint256 limit, bool activo) public onlyOwner {
        reward memory aux;
        aux.nftNeeds = idCardNeeds;
        aux.nftReward = rewards;
        aux.active = activo;
        aux.limit = limit;

        rewardsCollect[_rewardsTracker.current()] = aux;
        _rewardsTracker.increment();
    }

    function setOnOffReward(uint256 rewardId, bool toggle) public onlyOwner {
        rewardsCollect[rewardId].active = toggle;
    }

    function setLimitReward(uint256 rewardId, uint256 limit) public onlyOwner {
        rewardsCollect[rewardId].limit = limit;
    }

    function getReward(uint id) public view returns(uint256[] memory nftINeed, uint256[] memory nftRewards, uint256 limit, uint256 limitNow, bool activo) {
        require(id < _rewardsTracker.current(), "This rewards not exist.");
        return (rewardsCollect[id].nftNeeds, rewardsCollect[id].nftReward, rewardsCollect[id].limit, rewardsCollect[id].limitCounter.current(), rewardsCollect[id].active);
    }

    function canTakeReward(uint id) public returns(bool) {
        bool respuesta = false;

        if(id < _rewardsTracker.current() && rewardsCollect[id].active && checkIdCards(_msgSender(), id)) {

            if(rewardsCollect[id].limit != 0) {
                if(rewardsCollect[id].limitCounter.current() < rewardsCollect[id].limit){
                    respuesta = true;
                }
            } else {
                respuesta = true;
            }

        }

        return respuesta;
    }

    function takeReward(uint id) public {
        require(id < _rewardsTracker.current(), "This rewards not exist.");
        require(rewardsCollect[id].active, "This reward is not active.");
        //require(!checkWalletReward(_msgSender(), id), "You have already claimed this reward.");
        //require(checkCards(_msgSender(), id), "You do not have the necessary cards to claim the reward.");
        require(checkIdCards(_msgSender(), id), "You do not have the necessary cards to claim the reward.");
        
                
        if(rewardsCollect[id].limit != 0) {
            require(rewardsCollect[id].limitCounter.current() < rewardsCollect[id].limit, "Finished claims. Reached limit.");
        }

        //rewardsCollect[id].walletsClaimed[rewardsCollect[id].limitCounter.current()] = _msgSender();
        rewardsCollect[id].limitCounter.increment();
        mintRewardCards(_msgSender(), rewardsCollect[id].nftReward);
        
    }

    /*
    function checkWalletReward(address _owner, uint256 rewardId) internal view returns(bool) {
        bool respuesta = false;
        uint256 contador;
        while(!respuesta && contador < rewardsCollect[rewardId].limitCounter.current()) {
            if(rewardsCollect[rewardId].walletsClaimed[contador] == _owner) {
                respuesta = true;
            }
        }

        return respuesta;
    }
    */

    /* VERSION CON ID DE CARTAS ORIGINALES

    function checkCards(address _owner, uint256 rId) internal returns(bool) {
        //uint256[] memory userTokenTypes = getUserTokenTypes(_owner);
        uint256[] memory tokenIds = getTokenNotUsedIds(_owner);
        uint256[] memory _nftNeeds = rewardsCollect[rId].nftNeeds;
        bool[] memory checkingCards = new bool[](_nftNeeds.length);

        bool respuesta = false;
        uint256 tipo;

        for(uint i = 0; i < _nftNeeds.length; i++) {

            bool ok = false;
            uint256 counter = 0;

            while(!ok && counter < tokenIds.length) {

                tipo = getTokenType(tokenIds[counter]);

                if(_nftNeeds[i] == tipo) {
                    checkingCards[i] = true;
                    tokenInfo[tokenIds[counter]].usado = true;
                    ok = true;
                }

                counter += 1;
            }

        }

        // Se pueden devolver las que faltan para completar

        if(allTrue(checkingCards)) {
            respuesta = true;
        }

        return respuesta;
    }
    */

    function checkIdCards(address _owner, uint256 rId) internal returns(bool) {
        //uint256[] memory userTokenTypes = getUserTokenTypes(_owner);
        uint256[] memory tokenIds = getTokenNotUsedIds(_owner);
        uint256[] memory _nftNeeds = rewardsCollect[rId].nftNeeds;
        bool[] memory checkingCards = new bool[](_nftNeeds.length);

        bool respuesta = false;
        uint256 tipo;

        for(uint i = 0; i < _nftNeeds.length; i++) {

            bool ok = false;
            uint256 counter = 0;

            while(!ok && counter < tokenIds.length) {

                tipo = getTokenIdCard(tokenIds[counter]);

                if(_nftNeeds[i] == tipo) {
                    checkingCards[i] = true;
                    tokenInfo[tokenIds[counter]].usado = true;
                    ok = true;
                }

                counter += 1;
            }

        }

        // Se pueden devolver las que faltan para completar

        if(allTrue(checkingCards)) {
            respuesta = true;
        }

        return respuesta;
    }

    function allTrue(bool[] memory datos) internal pure returns(bool) {

        bool ok = true;
        uint contador = 0;
        while(contador < datos.length && ok) {
            if(datos[contador] == false) ok = false;
            contador += 1;
        }
        

        return ok;
    }

    /**********************************************
     **********************************************
                GETTERS NFTs POR TIPO
    **********************************************                    
    **********************************************/

    function getTokenInfo(uint256 tokenId) public view returns (uint idCard, uint256 typeNft, bool used) {
        require(tokenId < _tokenIdTracker.current(), "This token does not exist.");
        return (tokenInfo[tokenId].idCard, tokenInfo[tokenId].tipo, tokenInfo[tokenId].usado);
    }

    function getTokenSerial(uint256 tokenId) public view returns (string memory) {
        require(tokenId < _tokenIdTracker.current(), "This token does not exist.");

        uint tipo = getTokenType(tokenId);
        string memory nSerie = (tokenInfo[tokenId].serialNumber).toString();
        string memory nMax = (nftSupply[tipo].sMax).toString();

        string memory serial = string(abi.encodePacked(nSerie, "/", nMax));
        return serial;
    }

    function getTokenIds(address _owner) public view returns (uint256[] memory) {
        
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++)
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);

        return tokenIds;
    }

    function getTokenNotUsedIds(address _owner) public view returns (uint256[] memory) {
        
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);

        uint256 aux;
        uint256 contador = 0;

        for (uint256 i; i < ownerTokenCount; i++) {

            aux = tokenOfOwnerByIndex(_owner, i);

            if(tokenInfo[aux].usado == false) {
                tokenIds[contador] = aux;
                contador += 1;
            }

        }

        uint256[] memory devuelve = new uint256[](contador);

        for(uint j = 0; j < contador; j++) {
            devuelve[j] = tokenIds[j];
        }

        return devuelve;
    }

    function getTokenType(uint256 tokenId) public view returns (uint256) {
        require(tokenId < _tokenIdTracker.current(), "That token does not exist.");
        return tokenInfo[tokenId].tipo;
    }

    function getTokenIdCard(uint256 tokenId) public view returns (uint256) {
        require(tokenId < _tokenIdTracker.current(), "That token does not exist.");
        return tokenInfo[tokenId].idCard;
    }

    
    function getUserTokenTypes(address _owner) public view returns (uint256[] memory) {
        
        uint256[] memory tokenIds = getTokenIds(_owner);
        // -------------------
        uint256[] memory tokenTypes = new uint256[](getDifToken(_owner));
        for(uint i = 0; i < tokenTypes.length; i++) {
            tokenTypes[i] = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        }
        // -------------------
        uint256 aux;

        uint k = 0;

        for(uint i = 0; i < tokenIds.length; i++) {
            uint j = 0;
            bool esta = false;
            aux = tokenIds[i];

            while(j < tokenTypes.length && !esta) {
                if(tokenInfo[aux].tipo == tokenTypes[j]) {
                    esta = true;
                }
                j += 1;
            }
            if(!esta) {
                tokenTypes[k] = tokenInfo[aux].tipo;
                k += 1;
            }
        }

        return tokenTypes;
    }

    function getDifToken(address _owner) public view returns (uint256) {
        
        uint256[] memory tokenIds = getTokenIds(_owner);
        // -------------------------
        uint256[] memory tokenTypes = new uint256[](tokenIds.length);
        for(uint i = 0; i < tokenTypes.length; i++) {
            tokenTypes[i] = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        }
        // -------------------------
        uint256 aux;

        uint k = 0;

        for(uint i = 0; i < tokenIds.length; i++) {
            uint j = 0;
            bool esta = false;
            aux = tokenIds[i];

            while(j < tokenTypes.length && !esta) {
                if(tokenInfo[aux].tipo == tokenTypes[j]) {
                    esta = true;
                }
                j += 1;
            }
            if(!esta) {
                tokenTypes[k] = tokenInfo[aux].tipo;
                k += 1;
            }
        }

        return k;
    }

    function getTokenTypeCount(address _owner, uint256 tipo) public view returns (uint256) {
        
        uint256[] memory tokenIds = getTokenIds(_owner);
        uint256 contador = 0;
        uint256 aux;

        for(uint i = 0; i < tokenIds.length; i++) {
            aux = tokenIds[i];
            if(tokenInfo[aux].tipo == tipo)
                 contador += 1;
        }

        return contador;
    }

    function getTokenByType(address _owner, uint256 tipo) public view returns (uint256[] memory) {
        
        uint256[] memory tokens = getTokenIds(_owner);
        // ------------------------------------
        uint256[] memory tokensIds = new uint256[](tokens.length);
        for(uint i = 0; i < tokensIds.length; i++) {
            tokensIds[i] = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        }
        // ------------------------------------

        uint8 k = 0;
        
        for(uint i = 0; i < tokens.length; i++){
            if(tokenInfo[tokens[i]].tipo == tipo) {
                tokensIds[k] = tokens[i];
                k += 1;
            }
        }

        require(k > 0, "ERROR: You dont have NFTs of this type.");

        uint256[] memory devuelvo = new uint256[](k);
        for(uint i = 0; i < k; i++){
            devuelvo[i] = tokensIds[i];
        }

        return devuelvo;
    }

    
    function getTokenBalances(address _owner) public view returns (uint256[] memory, uint256[] memory) {
        
        uint256[] memory tokenTypes = getUserTokenTypes(_owner);
        uint256[] memory tokenAmount = new uint256[](tokenTypes.length);
        
        for(uint i = 0; i < tokenTypes.length; i++){
            tokenAmount[i] = getTokenTypeCount(_owner, tokenTypes[i]);
        }

        return (tokenTypes, tokenAmount);
    }
    

    /**********************************************
     **********************************************
                  GETTERs Y SETTERs
    **********************************************                    
    **********************************************/

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

        string memory _tokenType = tokenInfo[tokenId].tipo.toString();
        string memory _base = _baseURI();

        string memory _msgUri;

        if(tokenInfo[tokenId].usado) {
            _msgUri = string(abi.encodePacked(_tokenType, "-used"));
        } else {
            _msgUri = string(_tokenType);
        }
            
        return string(abi.encodePacked(_base, _msgUri));
    }

    function setBaseURI(string memory newUri) external onlyOwner() {
            _baseURIExtend = newUri;
    }

    /**********************************************
     **********************************************
                   ROYALTIES & OPENSEA
    **********************************************                    
    **********************************************/

    //Public wrapper of _exists
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
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
    **/
    function isApprovedForAll(address _owner, address _operator) public override(ERC721, IERC721) view returns (bool isOperator) {
      // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == OpenSeaAddress) {
            return true;
        }
        
        // otherwise, use the default ERC721.isApprovedForAll()
        return super.isApprovedForAll(_owner, _operator);
    }

    function setOpenSeaAddress(address newAdd) public onlyOwner {
        OpenSeaAddress = newAdd;
    }

    function getOpenSeaAddress() public view returns (address) {
        return OpenSeaAddress;
    }

}