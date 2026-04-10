/// SocketCAN constants matching linux/can.h, linux/can/raw.h,
/// linux/can/bcm.h, linux/can/isotp.h, linux/can/j1939.h.
library;

// Address family
const int afCan = 29; // AF_CAN

// Socket types
const int sockRaw = 3; // SOCK_RAW
const int sockDgram = 2; // SOCK_DGRAM

// CAN protocol families
const int canRaw = 1; // CAN_RAW
const int canBcm = 2; // CAN_BCM
const int canIsotp = 6; // CAN_ISOTP
const int canJ1939 = 7; // CAN_J1939

// ioctl
const int siocgifindex = 0x8933; // SIOCGIFINDEX

// SOL_CAN_BASE + CAN_RAW
const int solCanBase = 100;
const int solCanRaw = solCanBase + canRaw;

// CAN_RAW socket options
const int canRawFilter = 1; // CAN_RAW_FILTER
const int canRawErrFilter = 2; // CAN_RAW_ERR_FILTER
const int canRawLoopback = 3; // CAN_RAW_LOOPBACK
const int canRawRecvOwnMsgs = 4; // CAN_RAW_RECV_OWN_MSGS
const int canRawFdFrames = 5; // CAN_RAW_FD_FRAMES
const int canRawJoinFilters = 6; // CAN_RAW_JOIN_FILTERS

// CAN frame flags (in can_id)
const int canEffFlag = 0x80000000; // EFF/SFF flag (extended frame format)
const int canRtrFlag = 0x40000000; // RTR flag (remote transmission request)
const int canErrFlag = 0x20000000; // error message frame flag

// CAN ID masks
const int canSffMask = 0x000007FF; // standard frame format (SFF) mask
const int canEffMask = 0x1FFFFFFF; // extended frame format (EFF) mask
const int canErrMask = 0x1FFFFFFF; // error mask

// CAN frame sizes
const int canMaxDlc = 8; // CAN max data length code
const int canfdMaxDlc = 64; // CAN FD max data length code
const int canMtu = 16; // sizeof(struct can_frame)
const int canfdMtu = 72; // sizeof(struct canfd_frame)

// CAN FD flags (in canfd_frame.flags)
const int canfdBrs = 0x01; // bit rate switch
const int canfdEsi = 0x02; // error state indicator

// CAN error classes (for error frames)
const int canErrTxTimeout = 0x00000001;
const int canErrLostArb = 0x00000002;
const int canErrCrtl = 0x00000004;
const int canErrProt = 0x00000008;
const int canErrTrx = 0x00000010;
const int canErrAck = 0x00000020;
const int canErrBusOff = 0x00000040;
const int canErrBusError = 0x00000080;
const int canErrRestarted = 0x00000100;

// poll() events
const int pollIn = 0x0001; // POLLIN

// Sizes for ifreq
const int ifNameSize = 16; // IFNAMSIZ
const int ifreqSize = 40; // sizeof(struct ifreq) on 64-bit

// SOL_SOCKET
const int solSocket = 1;
const int soTimestamp = 29; // SO_TIMESTAMP

// BCM opcodes
const int txSetup = 1; // TX_SETUP
const int txDelete = 2; // TX_DELETE
const int txRead = 3; // TX_READ
const int rxSetup = 5; // RX_SETUP
const int rxDelete = 6; // RX_DELETE
const int rxRead = 7; // RX_READ

// BCM flags
const int settimer = 0x0001;
const int starttimer = 0x0002;
const int txCountevt = 0x0004;
const int txAnnounce = 0x0008;
const int txCpCanId = 0x0010;
const int rxFilterId = 0x0020;
const int rxCheckUpdate = 0x0040;
const int rxNoAutotimer = 0x0080;
const int rxAnnounceResume = 0x0100;
const int txResetMultiIdx = 0x0200;

// ISO-TP socket options (SOL_CAN_ISOTP = SOL_CAN_BASE + CAN_ISOTP)
const int solCanIsotp = solCanBase + canIsotp;
const int canIsotpOpts = 1; // CAN_ISOTP_OPTS
const int canIsotpRecvFc = 2; // CAN_ISOTP_RECV_FC
const int canIsotpTxStmin = 3; // CAN_ISOTP_TX_STMIN
const int canIsotpRxStmin = 4; // CAN_ISOTP_RX_STMIN
const int canIsotpLlOpts = 5; // CAN_ISOTP_LL_OPTS

// J1939 socket options (SOL_CAN_J1939 = SOL_CAN_BASE + CAN_J1939)
const int solCanJ1939 = solCanBase + canJ1939;
const int soJ1939Filter = 1; // SO_J1939_FILTER
const int soJ1939Promisc = 2; // SO_J1939_PROMISC
const int soJ1939ErrQueue = 3; // SO_J1939_ERRQUEUE

// J1939 constants
const int j1939NoPgn = 0x40000; // J1939_NO_PGN
const int j1939NoAddr = 0xFF; // J1939_NO_ADDR
const int j1939NoName = 0; // J1939_NO_NAME
