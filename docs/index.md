---
title: Overview
layout: default
nav_order: 1
---

<div class="conduit-hero">
  <p class="conduit-kicker">jajera · privatelink-conduit</p>
  <h1>PrivateLink Conduit</h1>
  <p class="conduit-lede">
    A runnable lab for cross-account AWS PrivateLink into a private 3-tier config API —
    same-Region and cross-Region — plus why New Zealand (<code>ap-southeast-6</code>)
    cannot join the cross-Region path today.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/walkthrough/">Deploy the lab</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/architecture/">See architecture</a>
  </div>
</div>

## Three paths

<div class="path-grid">
  <a class="path-card" href="{{ site.baseurl }}/walkthrough/">
    <span class="path-card__label">Same-Region</span>
    <strong>Sydney → Sydney</strong>
    <p>Sandbox consumer reaches the shared-services API in <code>ap-southeast-2</code>.</p>
    <span class="path-card__meta">config.conduit.internal</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/cross-region/">
    <span class="path-card__label">Cross-Region</span>
    <strong>Melbourne → Sydney</strong>
    <p>Native cross-Region PrivateLink with <code>supported_regions</code> + <code>service_region</code>.</p>
    <span class="path-card__meta">config-xr.conduit.internal</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/nz-limitation/">
    <span class="path-card__label path-card__label--warn">Documented gap</span>
    <strong>NZ is not available</strong>
    <p><code>ap-southeast-6</code> works same-Region only. Cross-Region is rejected in both directions.</p>
    <span class="path-card__meta">no stack shipped</span>
  </a>
</div>

## What this covers

**The pattern.** A consumer account reaches a private API in a provider account over
PrivateLink — no peering, Transit Gateway, IGW, or NAT. One TCP port on one consumer ENI.
The lab proves success (`"source": "rds"`) and isolation (direct app/RDS IPs time out).

**One provider, two consumers.** Sydney serves Sydney in-Region and Melbourne across Regions
on the **same** endpoint service.

{: .finding }
> Same-Region PrivateLink works in `ap-southeast-6`. **Cross-Region** does not, in either
> direction. Melbourne (`ap-southeast-4`) is the working cross-Region reference.
> Details: [Cross-Region]({{ site.baseurl }}/cross-region/) ·
> [Lab findings]({{ site.baseurl }}/nz-limitation/).

## Read in this order

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/architecture/">
    <strong>1. Architecture</strong>
    <span>Topology, tiers, CIDRs, sample API</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/privatelink/">
    <strong>2. How PrivateLink works</strong>
    <span>Roles, DNS, client IP, security groups</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/cross-region/">
    <strong>3. Cross-Region PrivateLink</strong>
    <span>The two knobs and the Melbourne path</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/nz-limitation/">
    <strong>4. Lab findings: New Zealand</strong>
    <span>What we observed for ap-southeast-6</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/walkthrough/">
    <strong>5. Deploy and destroy</strong>
    <span>Apply, prove (including isolation), tear down</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/troubleshooting/">
    <strong>Troubleshooting</strong>
    <span>Failure signatures and fixes</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/connectivity-options/">
    <strong>Alternatives and limits</strong>
    <span>What AWS cannot do; excluded workarounds</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/reference/">
    <strong>Terraform reference</strong>
    <span>File map for the three roots</span>
  </a>
</div>

{: .cost }
> Billable while running: RDS, NLB, interface endpoints, EC2 per stack. Follow
> [teardown]({{ site.baseurl }}/walkthrough/#destroy); destroy consumers before the provider.

## Prerequisites in brief

- Terraform >= 1.5, AWS provider ~> 5.0
- Profiles `shared-services` and `sandbox` (different accounts)
- Session Manager plugin
- Melbourne path: both accounts opted into `ap-southeast-4` (provider must opt in before
  listing it in `SupportedRegions`)

Full detail in the [walkthrough]({{ site.baseurl }}/walkthrough/#prerequisites).
