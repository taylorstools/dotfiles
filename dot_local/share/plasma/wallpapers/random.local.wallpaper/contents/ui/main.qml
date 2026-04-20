/*
    SPDX-FileCopyrightText: 2025 adolfo aka zayronxio <adolfo@librepixels.com>

    SPDX-License-Identifier: Apache-1.0
*/

import QtQuick
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami as Kirigami
import Qt.labs.folderlistmodel 2.15

WallpaperItem {
    id: root

    property url currentImageUrl
    property url defaultUrl: "image/bitmap.webp"

    function randonWallpaper(){
        var num = Math.floor(Math.random() * imagesModel.count)
        console.log(imagesModel.get(num, "filePath"))
        currentImageUrl = imagesModel.get(num, "filePath")
    }

    onCurrentImageUrlChanged: {
        oldImage.source = currentImageUrl
    }

    contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Wallpaper")
            icon.name: "view-refresh"
            onTriggered: Qt.callLater(randonWallpaper)
        }
    ]

    FolderListModel {
        id: imagesModel
        folder: root.configuration.wallpapersPath
        showDirs: true
        nameFilters: ["*.jpg", "*.png", "*.jpeg", "*.webp"]

        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                randonWallpaper()
            }
        }
    }



    Image {
        id: bs
        anchors.fill: parent
        source: defaultUrl
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status === Image.Ready) {
                oldImage.opacity = 0.0
            }
        }
    }
    Image {
        id: oldImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        opacity: 0.0
        onStatusChanged: {
            if (status === Image.Ready) {
                fadeFirsAnimation.start()

            }
        }

    }

    SequentialAnimation {
        id: fadeFirsAnimation
        PropertyAnimation { target: oldImage; property: "opacity"; to: 1.0; duration: 1500 }
        ScriptAction {
            script: {
                bs.source = currentImageUrl
            }
        }
    }
    Timer {
        id: retry
        interval: 1200
        running: true
        repeat: true
        onTriggered: {
            if (!oldImage.source && imagesModel.count > 0) {
                retry.repeat = false
                randonWallpaper()
                retry.stop()
            } else if (oldImage.source) {
                retry.repeat = false
                retry.stop()
            }

        }
    }
    Timer {
        id: timer
        interval: root.configuration.interval * 60000
        running: true
        repeat: true
        onTriggered: {
            randonWallpaper()
        }
    }
}

