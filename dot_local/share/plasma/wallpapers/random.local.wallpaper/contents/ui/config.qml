/*
    SPDX-FileCopyrightText: 2025 Adolfo aka zayronxio <adolfo@librepixels.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls
import Qt.labs.platform
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
//import Qt.labs.folderlistmodel 2.15

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout


    property alias cfg_wallpapersPath: folderDialog.folder
    property alias cfg_interval: intervalUpdate.value

    FolderDialog  {
        id: folderDialog
    }

    Button {
        text: folderDialog.folder ? folderDialog.folder : i18n("Select Folder:")
        enabled: folderMode.checked
        Kirigami.FormData.label: file.pathFolder
        onClicked: {
            folderDialog.open()
        }
    }

    SpinBox {
        id: intervalUpdate
        Kirigami.FormData.label: i18n("update frequency (minutes):")
        from: 15
        to: 1440
    }
}
