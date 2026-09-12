# -*- coding: utf-8 -*-
#
# Retro Pi 2.0 -- Apps
#
# Two screens:
#
#   /              the launcher: Games and YouTube
#   /?view=games   the games home: All Games, one entry per console, plus
#                  recently played and favourites
#
# The games home is built here rather than pointing at Advanced Kodi
# Launcher's own root, because that root also lists Sources, Launchers,
# Utilities and Global Reports. AKL has settings to hide the last two but
# not the first two, and they are configuration screens that have no place
# on a TV the whole house uses. Reading the collections straight out of
# AKL's database gives the same content with none of the clutter.
#
# Every item is a plain folder pointing at its real target. An earlier
# version routed clicks back through this plugin and answered with an
# ActivateWindow to hand the whole window over; Kodi treats a request that
# returns no listing as a failed GetDirectory and cancels the queued builtin
# along with it, so nothing happened at all. Linking directly is race-free,
# and Back still lands where it should.
import os
import sqlite3
import sys
import urllib.parse

import xbmc
import xbmcaddon
import xbmcgui
import xbmcplugin

ADDON = xbmcaddon.Addon()
ADDON_ID = ADDON.getAddonInfo('id')
HANDLE = int(sys.argv[1]) if len(sys.argv) > 1 else -1
BASE = 'plugin://%s/' % ADDON_ID

PROFILE = os.path.expanduser('~/.kodi/userdata')
AKL_DB = os.path.join(PROFILE, 'addon_data/plugin.program.akl/akl.db')
MEDIA = os.path.join(PROFILE, 'media/retropi2-apps')
AKL = 'plugin://plugin.program.akl'

# Listed first: it is what people want most of the time, and AKL's search
# only ever covers one collection.
ALL_GAMES = 'All Games'


def log(msg):
    xbmc.log('[retropi2.apps] %s' % msg, xbmc.LOGINFO)


def art_for(slug):
    """Portrait where a skin wants a poster, 16:9 where it wants a thumb.

    Supplying one aspect ratio means whichever view the skin picks stretches
    it, so both shapes exist and map to the keys that expect each.
    """
    wide = os.path.join(MEDIA, '%s.png' % slug)
    poster = os.path.join(MEDIA, '%s-poster.png' % slug)
    fan = os.path.join(MEDIA, '%s-fanart.jpg' % slug)

    art = {}
    if os.path.exists(poster):
        for key in ('poster', 'icon', 'keyart', 'thumb'):
            art[key] = poster
    if os.path.exists(wide):
        for key in ('landscape', 'banner'):
            art[key] = wide
        art.setdefault('thumb', wide)
    if os.path.exists(fan):
        art['fanart'] = fan
    return art


def slugify(text):
    out = ''.join(c.lower() if c.isalnum() else '-' for c in text)
    while '--' in out:
        out = out.replace('--', '-')
    return out.strip('-')


def query(sql, args=()):
    try:
        con = sqlite3.connect('file:%s?mode=ro' % AKL_DB, uri=True)
        rows = con.execute(sql, args).fetchall()
        con.close()
        return rows
    except Exception as exc:
        log('AKL database unavailable: %s' % exc)
        return []


def collections():
    """Every non-empty AKL collection with its count, All Games first."""
    rows = query(
        'SELECT c.name, c.id, '
        '  (SELECT count(*) FROM roms_in_romcollection r '
        '   WHERE r.romcollection_id = c.id) '
        'FROM romcollections c')
    out = [r for r in rows if r[2] > 0]
    out.sort(key=lambda r: (r[0] != ALL_GAMES, -r[2], r[0]))
    return out


def total_games():
    rows = query('SELECT count(*) FROM roms')
    return rows[0][0] if rows else 0


def add(label, target, plot='', slug=None, folder=True):
    item = xbmcgui.ListItem(label=label)
    item.setArt(art_for(slug or slugify(label)))
    info = item.getVideoInfoTag()
    info.setTitle(label)
    if plot:
        info.setPlot(plot)
    item.setProperty('IsPlayable', 'false')
    xbmcplugin.addDirectoryItem(HANDLE, target, item, isFolder=folder)


def view_launcher():
    xbmcplugin.setPluginCategory(HANDLE, 'Apps')
    xbmcplugin.setContent(HANDLE, 'files')

    n = total_games()
    games_plot = ('%s games across every console you have.' % format(n, ',')
                  if n else 'Your retro game library.')
    add('Games', BASE + '?view=games', slug='games', plot=games_plot)
    add('YouTube', 'plugin://plugin.video.youtube/', slug='youtube',
        plot='Search YouTube, browse trending, and play videos.')

    xbmcplugin.addSortMethod(HANDLE, xbmcplugin.SORT_METHOD_NONE)
    xbmcplugin.endOfDirectory(HANDLE, cacheToDisc=False)


def view_games():
    xbmcplugin.setPluginCategory(HANDLE, 'Games')
    xbmcplugin.setContent(HANDLE, 'files')

    cols = collections()
    if not cols:
        add('No games found yet', BASE, folder=False,
            plot='Copy ROMs into the roms share, then run '
                 'retropi2-setup-games on the box.')
        xbmcplugin.endOfDirectory(HANDLE, cacheToDisc=False)
        return

    for name, cid, count in cols:
        if name == ALL_GAMES:
            plot = ('Everything, all %s of them. Open the menu in here to '
                    'search by title.' % format(count, ','))
        else:
            plot = '%s games.' % format(count, ',')
        add(name, '%s/collection/%s' % (AKL, cid), plot=plot)

    add('Recently played', '%s/collection/virtual/recently_played' % AKL,
        slug='recently-played', plot='Pick up where you left off.')
    add('Favourites', '%s/collection/virtual/favourites' % AKL,
        slug='favourites', plot='Games you have starred.')

    xbmcplugin.addSortMethod(HANDLE, xbmcplugin.SORT_METHOD_NONE)
    xbmcplugin.endOfDirectory(HANDLE, cacheToDisc=False)


def main():
    args = urllib.parse.parse_qs(sys.argv[2][1:]) if len(sys.argv) > 2 else {}
    if args.get('view', [None])[0] == 'games':
        view_games()
    else:
        view_launcher()


if __name__ == '__main__':
    main()
