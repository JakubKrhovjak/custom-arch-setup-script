// Only T-Mobile internal hosts go through the SOCKS tunnel into the VPN VM; everything else stays direct.
// SSO/SAML domains belong here too, otherwise the login can hang half way.
function FindProxyForURL(url, host) {
  var internal = ["*.tmo", "*.tcko.net", "*.st.sk", "*.rdm.cz"];
  var viaVpn = internal.some(function (pattern) { return shExpMatch(host, pattern); });
  return viaVpn ? "SOCKS5 127.0.0.1:@SOCKS_PORT@" : "DIRECT";
}
