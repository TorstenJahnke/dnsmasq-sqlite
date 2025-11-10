HINWEIS:

1. block_regex     (Pattern)  		  -- IPSetTerminate
2. block_exact     (Hosts & Domain)   -- IPSetTerminate
3. block_wildcard  (Hosts & Domain)   -- IPSetDNSBlock
4. fqdn_dns_allow  (Hosts & Domain)   -- IPSetDNSAllow
5. fqdn_dns_block  (Hosts & Domain)   -- IPSetDNSBlock

IPv4/IPv6 Spalten entfernen (nicht mehr nötig!) > falsch!
1. IPSets bestehen aus IPv4 und IPv6 Adressen
2. IPv6 bevor IPv4 Regel. Antworten (Termination) müssen auch eine IPv6 Antwort bereitstellen.
