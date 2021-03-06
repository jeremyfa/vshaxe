package vshaxe;

import Vscode.*;
import vscode.*;

class LanguageServer {
    var context:ExtensionContext;
    var disposable:Disposable;
    var hxFileWatcher:FileSystemWatcher;
    var displayConfig:DisplayConfiguration;

    public var client(default,null):LanguageClient;

    public function new(context:ExtensionContext) {
        this.context = context;

        displayConfig = new DisplayConfiguration(context);
        context.subscriptions.push(window.onDidChangeActiveTextEditor(onDidChangeActiveTextEditor));
    }

    function onDidChangeActiveTextEditor(editor:TextEditor) {
        if (editor != null && editor.document.languageId == "haxe")
            client.sendNotification({method: "vshaxe/didChangeActiveTextEditor"}, {uri: editor.document.uri.toString()});
    }

    public function start() {
        var serverModule = context.asAbsolutePath("./server_wrapper.js");
        var serverOptions = {
            run: {module: serverModule, options: {env: js.Node.process.env}},
            debug: {module: serverModule, options: {env: js.Node.process.env, execArgv: ["--nolazy", "--debug=6004"]}}
        };
        var clientOptions = {
            documentSelector: "haxe",
            synchronize: {
                configurationSection: "haxe"
            },
            initializationOptions: {
                displayConfigurationIndex: displayConfig.getIndex()
            }
        };
        client = new LanguageClient("haxe", "Haxe", serverOptions, clientOptions);
        client.logFailedRequest = function(type, error) {
            client.warn('Request ${type.method} failed.', error);
        };
        client.onReady().then(function(_) {
            client.outputChannel.appendLine("Haxe language server started");
            displayConfig.onDidChangeIndex = function(index) {
                client.sendNotification({method: "vshaxe/didChangeDisplayConfigurationIndex"}, {index: index});
            }

            hxFileWatcher = workspace.createFileSystemWatcher("**/*.hx", false, true, true);
            context.subscriptions.push(hxFileWatcher.onDidCreate(function(uri) {
                var editor = window.activeTextEditor;
                if (editor == null || editor.document.uri.fsPath != uri.fsPath)
                    return;
                if (editor.document.getText(new Range(0, 0, 0, 1)).length > 0) // skip non-empty created files (can be created by e.g. copy-pasting)
                    return;

                client.sendRequest({method: "vshaxe/determinePackage"}, {fsPath: uri.fsPath}).then(function(result:{pack:String}) {
                    if (result.pack == "")
                        return;
                    editor.edit(function(edit) edit.insert(new Position(0, 0), 'package ${result.pack};\n'));
                });
            }));
            context.subscriptions.push(hxFileWatcher);

            #if debug
            client.onNotification({method: "vshaxe/updateParseTree"}, function(result:{uri:String, parseTree:String}) {
                commands.executeCommand("hxparservis.updateParseTree", result.uri, result.parseTree);
            });
            #end
        });
        disposable = client.start();
        context.subscriptions.push(disposable);
    }

    public function restart() {
        if (client != null && client.outputChannel != null)
            client.outputChannel.dispose();

        if (disposable != null) {
            context.subscriptions.remove(disposable);
            disposable.dispose();
            disposable = null;
        }
        if (hxFileWatcher != null) {
            context.subscriptions.remove(hxFileWatcher);
            hxFileWatcher.dispose();
            hxFileWatcher = null;
        }
        start();
    }
}