package com.ipjoker.app

import android.net.VpnService

/**
 * Android VPN service declaration only.
 * No TUN interface is established until a real proxy engine is integrated.
 */
class IpJokerVpnService : VpnService()
